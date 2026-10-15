#!/usr/bin/env python3
"""Test orchestrator for hotkit.

  python tools/test.py lint          static checks (no AutoHotkey needed)
  python tools/test.py validate      AutoHotkey /Validate on every entry script
  python tools/test.py unit          headless unit tests (tests/unit)
  python tools/test.py integration   --check / --list-actions against fixtures, docs sync
  python tools/test.py e2e           live process driven by synthetic keystrokes
  python tools/test.py all           everything above, in order
  python tools/test.py mutation      mutation testing (slow; see tools/mutate.py)

Exit status is non-zero when any selected stage fails.
"""
from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ahk  # noqa: E402
import lint  # noqa: E402

REPO = ahk.REPO
MAIN = REPO / "src" / "Main.ahk"
ENTRY_SCRIPTS = [MAIN, REPO / "tests/unit/RunUnit.ahk", REPO / "tests/e2e/RunE2E.ahk"]


def stage_lint() -> bool:
    return lint.main([]) == 0


def stage_validate() -> bool:
    ok = True
    for script in ENTRY_SCRIPTS:
        r = ahk.validate(script)
        status = "ok" if r.code == 0 else "FAIL"
        print(f"validate {script.relative_to(REPO)}: {status}")
        if r.code != 0:
            print(r.out)
            ok = False
    return ok


def _tap(result: ahk.Result, name: str) -> bool:
    print(result.out)
    if result.timed_out:
        print(f"{name}: timed out")
    return result.code == 0


def stage_unit(filter_: str = "") -> bool:
    args = [f"--filter={filter_}"] if filter_ else []
    return _tap(ahk.run(REPO / "tests/unit/RunUnit.ahk", *args, timeout=300), "unit")


def stage_integration() -> bool:
    ok = True
    fixtures = REPO / "tests/integration/fixtures"
    expectations = json.loads((REPO / "tests/integration/expectations.json").read_text())
    cases = [(REPO / "config/config.example.json", {"exit": 0, "contains": ["OK"]})]
    cases += [(fixtures / name, exp) for name, exp in expectations.items()]
    with tempfile.TemporaryDirectory() as empty_dir:
        for path, exp in cases:
            r = ahk.run(MAIN, "--check", "--no-plugin-sync", "--config-dir", ahk.to_ahk_path(empty_dir),
                        "--config", ahk.to_ahk_path(path))
            problems = []
            if r.code != exp["exit"]:
                problems.append(f"exit {r.code}, expected {exp['exit']}")
            for needle in exp["contains"]:
                if needle not in r.out:
                    problems.append(f"missing output: {needle!r}")
            print(f"integration {path.name}: {'ok' if not problems else 'FAIL'}")
            if problems:
                ok = False
                print("  " + "\n  ".join(problems))
                print("  output:\n    " + r.out.replace("\n", "\n    "))
        ok = check_actions_doc(empty_dir) and ok
    return ok


def list_actions(config_dir: str) -> list[dict]:
    r = ahk.run(MAIN, "--list-actions", "--no-plugin-sync", "--config-dir", ahk.to_ahk_path(config_dir),
                "--config", ahk.to_ahk_path(REPO / "config/config.example.json"))
    if r.code != 0:
        raise RuntimeError("--list-actions failed:\n" + r.out)
    start = r.out.index("[")
    return [a for a in json.loads(r.out[start:]) if not a["module"].startswith("plugin:")]


def check_actions_doc(config_dir: str) -> bool:
    """docs/actions.md must match the registered actions (regenerate with tools/gen_docs.py)."""
    import gen_docs

    actions = list_actions(config_dir)
    expected = gen_docs.render(actions)
    current = (REPO / "docs/actions.md").read_text(encoding="utf-8")
    if current != expected:
        print("integration docs/actions.md: FAIL (stale; run python tools/gen_docs.py)")
        return False
    print(f"integration docs/actions.md: ok ({len(actions)} actions)")
    return True


def stage_e2e() -> bool:
    stub = REPO / "local" / "plugins.generated.ahk"
    backup = stub.read_bytes() if stub.exists() else None
    try:
        return _tap(ahk.run(REPO / "tests/e2e/RunE2E.ahk", timeout=300), "e2e")
    finally:
        # The e2e app rewrites the plugin stub for its fixture; restore the developer's.
        if backup is None:
            stub.unlink(missing_ok=True)
        else:
            stub.write_bytes(backup)


def stage_mutation(extra: list[str]) -> bool:
    import mutate

    return mutate.main(extra) == 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("stage", choices=["lint", "validate", "unit", "integration", "e2e", "all", "mutation"])
    parser.add_argument("--filter", default="", help="unit test name filter")
    args, extra = parser.parse_known_args(argv)
    stages = {
        "lint": stage_lint,
        "validate": stage_validate,
        "unit": lambda: stage_unit(args.filter),
        "integration": stage_integration,
        "e2e": stage_e2e,
    }
    if args.stage == "mutation":
        return 0 if stage_mutation(extra) else 1
    selected = list(stages) if args.stage == "all" else [args.stage]
    failed = []
    for name in selected:
        print(f"==> {name}")
        if not stages[name]():
            failed.append(name)
    print("==> " + ("FAILED: " + ", ".join(failed) if failed else "all stages passed"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
