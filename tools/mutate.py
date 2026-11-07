#!/usr/bin/env python3
"""Mutation testing: does the unit suite notice when the code is wrong?

Applies one small operator mutation at a time (== to !=, < to <=, && to ||,
true to false, +1 to -1, ...) to a copy of the repository, runs the unit
tests against the copy, and counts the mutant as killed when the suite fails.
Surviving mutants point at logic the tests do not pin down.

  python tools/mutate.py                   # sample 60 mutants, seed 1
  python tools/mutate.py --max 0           # every mutant (slow)
  python tools/mutate.py --file src/Core/Bindings.ahk --threshold 70

Lines between "; mutate: off" and "; mutate: on" comments are skipped: use
them around thin Win32/GUI wrappers that only e2e or manual testing can cover,
never around decision logic.

The working tree is never modified.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import queue
import random
import re
import shutil
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ahk  # noqa: E402

REPO = ahk.REPO

# Code whose logic the unit suite is expected to pin down. UI, Win32 and
# hardware wrappers are exercised by e2e or by hand and are excluded.
TARGETS = [
    "src/Core/ActionRegistry.ahk",
    "src/Core/Bindings.ahk",
    "src/Core/Config.ahk",
    "src/Core/Paths.ahk",
    "src/Core/Plugins.ahk",
    "src/Lib/HotkeyText.ahk",
    "src/Lib/WindowMatcher.ahk",
    "src/Lib/FocusHistory.ahk",
    "src/Lib/DisplayBrightness.ahk",
    "src/Lib/DisplayScale.ahk",
    "src/Ui/ShortcutOsd.ahk",
]

# (name, pattern, replacement). Patterns run on code with strings and comments masked.
OPERATORS = [
    ("eq->ne", re.compile(r"(?<![:!<>=.])=(?![=>])"), "!="),
    ("ne->eq", re.compile(r"!=(?!=)"), "="),
    ("lt->le", re.compile(r"(?<![<\-])<(?![=<^!+#])"), "<="),
    ("le->lt", re.compile(r"<="), "<"),
    ("gt->ge", re.compile(r"(?<![>\-=])>(?![=>^!+#])"), ">="),
    ("ge->gt", re.compile(r">="), ">"),
    ("and->or", re.compile(r"&&"), "||"),
    ("or->and", re.compile(r"\|\|"), "&&"),
    ("true->false", re.compile(r"\btrue\b", re.I), "false"),
    ("false->true", re.compile(r"\bfalse\b", re.I), "true"),
    ("plus1->minus1", re.compile(r"\+ 1\b"), "- 1"),
    ("minus1->plus1", re.compile(r"- 1\b"), "+ 1"),
    ("not-removed", re.compile(r"(?<![!=<>])!(?![=])(?=[A-Za-z(])"), ""),
]

MARKER = re.compile(r"^;\s*mutate:\s*(on|off)\b", re.I)
RETURN = re.compile(r"\breturn\s+(\S.*?)\s*$")
TRIVIAL_RETURN = {'""', "''", "false", "0", "true", "1"}
SKIP_LINE = re.compile(r"^\s*(;|#|static\s+\w+\s*:=|class\s|\}|\{$)")


@dataclass
class Mutant:
    file: str
    line: int
    op: str
    original: str
    mutated: str


def mask(line: str) -> str:
    """Replaces string literals and trailing comments with filler so operators inside them are ignored."""
    out, quote, i = [], "", 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "`" and i + 1 < len(line):
                out += "__"
                i += 2
                continue
            out.append("_" if c != quote else c)
            if c == quote:
                quote = ""
        elif c in "\"'":
            quote = c
            out.append(c)
        elif c == ";" and (i == 0 or line[i - 1] in " \t"):
            out.append(" " * (len(line) - i))
            break
        else:
            out.append(c)
        i += 1
    return "".join(out)


def generate(files: list[str]) -> list[Mutant]:
    mutants = []
    for rel in files:
        lines = (REPO / rel).read_text(encoding="utf-8").splitlines()
        in_block_comment = False
        enabled = True
        for n, line in enumerate(lines, 1):
            stripped = line.strip()
            if MARKER.match(stripped):
                enabled = MARKER.match(stripped).group(1).lower() == "on"
                continue
            if not enabled:
                continue
            if stripped.startswith("/*"):
                in_block_comment = True
            if in_block_comment:
                in_block_comment = not stripped.endswith("*/")
                continue
            if not stripped or SKIP_LINE.match(line) or "::" in line:
                continue
            masked = mask(line)
            for name, pattern, repl in OPERATORS:
                for m in pattern.finditer(masked):
                    mutated = line[: m.start()] + repl + line[m.end():]
                    if mutated != line:
                        mutants.append(Mutant(rel, n, name, line, mutated))
            # return-blank: the function returns "" instead of its value.
            m = RETURN.search(masked)
            if m and m.group(1).lower() not in TRIVIAL_RETURN and not m.group(1).endswith(("{", "(", "[", ",")):
                mutated = line[: m.start()] + 'return ""' + line[m.end(1):]
                mutants.append(Mutant(rel, n, "return-blank", line, mutated))
    return mutants


def run_mutant(mutant: Mutant, workdir: Path, timeout: int) -> str:
    target = workdir / mutant.file
    original = target.read_text(encoding="utf-8")
    lines = original.splitlines(keepends=True)
    ending = "\n" if lines[mutant.line - 1].endswith("\n") else ""
    lines[mutant.line - 1] = mutant.mutated + ending
    target.write_text("".join(lines), encoding="utf-8")
    try:
        r = ahk.run(workdir / "tests/unit/RunUnit.ahk", timeout=timeout)
    finally:
        target.write_text(original, encoding="utf-8")
    if r.timed_out:
        return "error"  # a hung runner is not evidence that a test killed the mutant
    if "TAP version" not in r.out:
        if r.code == 0:
            return "error"  # no test output at all: the runner did not start
        return "invalid"  # the mutant does not load; says nothing about the tests
    if r.code != 0:
        return "killed"
    # Survived only when the suite reports a full pass for the whole plan.
    m = re.search(r"^# (\d+)/(\d+) passed", r.out, re.M)
    return "survived" if m and m.group(1) == m.group(2) else "error"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--file", action="append", help="limit to these files (repeatable)")
    parser.add_argument("--max", type=int, default=60, help="sample size; 0 runs every mutant")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--threshold", type=float, default=90.0, help="minimum mutation score (percent)")
    parser.add_argument("--timeout", type=int, default=60, help="seconds per unit-test run")
    parser.add_argument("--list", action="store_true", help="list mutants without running them")
    parser.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1), help="parallel test runs")
    parser.add_argument("--report", help="write surviving mutants to this file")
    parser.add_argument("--json-report", help="write machine-readable completion and finding evidence")
    args = parser.parse_args(argv)
    if args.max < 0 or not 0 <= args.threshold <= 100 or args.jobs < 1:
        parser.error("max must be non-negative, threshold 0..100, and jobs positive")

    evidence = {"schema": 1, "status": "incomplete", "full_scope": False,
                "commit": os.environ.get("GITHUB_SHA"), "run_id": os.environ.get("GITHUB_RUN_ID"),
                "attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
                "reason": "The runner did not complete.", "threshold": args.threshold}

    def save_evidence():
        if args.json_report:
            Path(args.json_report).write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")

    save_evidence()  # setup failures must not leave an old successful report behind

    mutants = generate(args.file or TARGETS)
    available = len(mutants)
    if args.max and len(mutants) > args.max:
        mutants = sorted(random.Random(args.seed).sample(mutants, args.max), key=lambda m: (m.file, m.line))
    if args.list:
        for m in mutants:
            print(f"{m.file}:{m.line} {m.op}: {m.mutated.strip()}")
        return 0

    with tempfile.TemporaryDirectory() as tmp:
        workdirs: queue.Queue[Path] = queue.Queue()
        for j in range(max(1, args.jobs)):
            workdir = Path(tmp) / f"repo{j}"
            shutil.copytree(REPO, workdir, ignore=shutil.ignore_patterns(".git", "local", "__pycache__"))
            workdirs.put(workdir)
        baseline = ahk.run(Path(tmp) / "repo0" / "tests/unit/RunUnit.ahk", timeout=args.timeout)
        passed = re.search(r"^# (\d+)/(\d+) passed", baseline.out, re.M)
        if (baseline.code != 0 or baseline.timed_out or "TAP version" not in baseline.out
                or not passed or int(passed.group(1)) == 0 or passed.group(1) != passed.group(2)):
            print(baseline.out)
            print("mutation: unit tests fail before mutation; fix them first")
            return 2

        def work(m: Mutant) -> str:
            workdir = workdirs.get()
            try:
                for _ in range(3):  # retry runner hiccups, not test results
                    outcome = run_mutant(m, workdir, args.timeout)
                    if outcome != "error":
                        return outcome
                return outcome
            finally:
                workdirs.put(workdir)

        survivors, invalid, errors = [], 0, 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            for i, (m, outcome) in enumerate(zip(mutants, pool.map(work, mutants)), 1):
                print(f"[{i}/{len(mutants)}] {outcome:16} {m.file}:{m.line} {m.op}", flush=True)
                if outcome == "survived":
                    survivors.append(m)
                elif outcome == "invalid":
                    invalid += 1
                elif outcome != "killed":
                    errors += 1

    valid = len(mutants) - invalid - errors
    killed = valid - len(survivors)
    score = 100.0 * killed / valid if valid else 100.0
    lines = [f"  {m.file}:{m.line} {m.op}\n    - {m.original.strip()}\n    + {m.mutated.strip()}" for m in survivors]
    if survivors:
        print("\nSurviving mutants (tests did not notice):")
        print("\n".join(lines))
    if args.report:
        Path(args.report).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"\nmutation score: {score:.1f}% ({killed}/{valid} killed, {invalid} invalid, threshold {args.threshold:.0f}%)")
    evidence.update(full_scope=not args.file and len(mutants) == available,
                    selected=len(mutants), executed=len(mutants), available=available,
                    killed=killed, survived=len(survivors), invalid=invalid, errors=errors,
                    score=score, status="incomplete" if errors or not valid else
                    "findings" if score < args.threshold else "healthy",
                    reason="Runner errors or no valid mutants." if errors or not valid else "Completed.",
                    survivors=[{"file": m.file, "line": m.line, "operator": m.op} for m in survivors])
    save_evidence()
    if errors or not valid:
        return 2
    return 0 if score >= args.threshold else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
