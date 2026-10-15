#!/usr/bin/env python3
"""Static checks for the repository. No AutoHotkey required.

Rules (ids shown in output):
  AHK001  .ahk files start with `#Requires AutoHotkey v2.0`
  AHK002  no hotkey labels (`x::`) under src/ — bind keys through config
  AHK003  library files (src/Lib) carry no #SingleInstance / #Warn / #NoTrayIcon
  AHK004  #Include targets exist
  AHK005  no AutoHotkey v1 command syntax (`MsgBox, ...`)
  TXT001  UTF-8 without BOM
  TXT002  LF line endings, no trailing whitespace, final newline
  TXT003  no tab indentation in .ahk/.py/.json/.md
  PRV001  no personal paths (C:\\Users\\<name>, /home/<name>) in tracked files
  PRV002  no denylisted private terms (.private-terms file or PRIVATE_TERMS env)
  TST001  every tests/unit/*.Test.ahk is included by tests/unit/RunUnit.ahk
  CFG001  config/config.example.json parses and matches config/config.schema.json
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TEXT_SUFFIXES = {".ahk", ".py", ".json", ".md", ".yml", ".yaml", ".txt", ".ps1", ".cfg", ".toml", ""}
SKIP_DIRS = {".git", "local", "__pycache__", ".venv", "node_modules"}

HOTKEY_LABEL = re.compile(r"""^\s*[^\s;"'(][^"'(]*?::\s*(\{|$|[A-Za-z_(])""")
V1_COMMAND = re.compile(r"^\s*(MsgBox|Send|SendInput|Run|Sleep|WinActivate|IfWinExist|IfWinActive|StringReplace|SetTimer|Gosub|Goto)\s*,", re.I)
PERSONAL_PATH = re.compile(r"[A-Za-z]:\\\\?Users\\\\?(?!Public|Default|<|%|\{|\.\.\.)[A-Za-z0-9._-]+|/home/(?!runner|user\b|<)[a-z0-9._-]+/", re.I)
INCLUDE = re.compile(r"^\s*#Include\s+(\*i\s+)?(.+?)\s*(;.*)?$", re.I)


def tracked_files() -> list[Path]:
    try:
        out = subprocess.run(["git", "ls-files", "-co", "--exclude-standard"], cwd=REPO,
                             capture_output=True, text=True, check=True).stdout
        files = [REPO / f for f in out.splitlines() if f]
    except (subprocess.CalledProcessError, FileNotFoundError):
        files = [p for p in REPO.rglob("*") if p.is_file()]
    return [f for f in files if f.exists() and not (set(f.relative_to(REPO).parts) & SKIP_DIRS)]


def private_terms() -> list[str]:
    terms = []
    path = REPO / ".private-terms"
    if path.exists():
        terms += [t.strip() for t in path.read_text(encoding="utf-8").splitlines()]
    terms += [t.strip() for t in os.environ.get("PRIVATE_TERMS", "").splitlines()]
    return [t for t in terms if t and not t.startswith("#")]


def resolve_include(src: Path, target: str) -> Path | None:
    target = target.strip().strip('"')
    if target.startswith("<") and target.endswith(">"):
        name = target[1:-1]
        candidates = [REPO / "src" / "Lib" / f"{name}.ahk"]
        return next((c for c in candidates if c.exists()), candidates[0])
    target = target.replace("%A_LineFile%", str(src))
    target = target.replace("%A_ScriptDir%", str(src.parent))
    if "%" in target:
        return None
    return Path(os.path.normpath(target.replace("\\", "/")))


def lint_file(path: Path, terms: list[str]) -> list[str]:
    rel = path.relative_to(REPO).as_posix()
    problems: list[str] = []
    raw = path.read_bytes()
    if path.suffix not in TEXT_SUFFIXES or b"\0" in raw[:4096]:
        return problems
    if raw.startswith(b"\xef\xbb\xbf"):
        problems.append(f"{rel}: TXT001 UTF-8 BOM")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return [f"{rel}: TXT001 not valid UTF-8"]
    if "\r\n" in text:
        problems.append(f"{rel}: TXT002 CRLF line endings")
    if text and not text.endswith("\n"):
        problems.append(f"{rel}: TXT002 missing final newline")
    lines = text.splitlines()
    for n, line in enumerate(lines, 1):
        if line != line.rstrip():
            problems.append(f"{rel}:{n}: TXT002 trailing whitespace")
        if path.suffix in {".ahk", ".py", ".json", ".md"} and line.startswith("\t"):
            problems.append(f"{rel}:{n}: TXT003 tab indentation")
        if rel != "tools/lint.py" and PERSONAL_PATH.search(line):
            problems.append(f"{rel}:{n}: PRV001 personal path: {PERSONAL_PATH.search(line).group(0)}")
        lower = line.lower()
        for term in terms:
            if term.lower() in lower:
                problems.append(f"{rel}:{n}: PRV002 private term")
    if path.suffix == ".ahk":
        problems += lint_ahk(path, rel, lines)
    return problems


def lint_ahk(path: Path, rel: str, lines: list[str]) -> list[str]:
    problems = []
    code = [l for l in lines if l.strip() and not l.strip().startswith(";")]
    if not code or code[0].strip() != "#Requires AutoHotkey v2.0":
        problems.append(f"{rel}: AHK001 first statement must be '#Requires AutoHotkey v2.0'")
    in_block_comment = False
    for n, line in enumerate(lines, 1):
        s = line.strip()
        if s.startswith("/*"):
            in_block_comment = True
        if in_block_comment:
            if s.endswith("*/") or s.startswith("*/"):
                in_block_comment = False
            continue
        if s.startswith(";"):
            continue
        if rel.startswith("src/") and HOTKEY_LABEL.match(line) and not s.startswith(("case ", "default")):
            problems.append(f"{rel}:{n}: AHK002 hotkey label in src/; register keys through config/Bindings")
        if rel.startswith("src/Lib/") and re.match(r"#(SingleInstance|Warn|NoTrayIcon|Persistent)\b", s, re.I):
            problems.append(f"{rel}:{n}: AHK003 directive in library file")
        if V1_COMMAND.match(line):
            problems.append(f"{rel}:{n}: AHK005 v1 command syntax")
        m = INCLUDE.match(line)
        if m and not m.group(1):
            target = resolve_include(path, m.group(2))
            if target is not None and not target.exists():
                problems.append(f"{rel}:{n}: AHK004 #Include target not found: {m.group(2)}")
    return problems


def lint_tests() -> list[str]:
    runner = (REPO / "tests/unit/RunUnit.ahk").read_text(encoding="utf-8")
    return [f"tests/unit/{p.name}: TST001 not included by RunUnit.ahk"
            for p in sorted((REPO / "tests/unit").glob("*.Test.ahk")) if p.name not in runner]


def strip_jsonc(text: str) -> str:
    out, i, in_str = [], 0, False
    while i < len(text):
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\":
                out.append(text[i + 1]); i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True; out.append(c)
        elif text.startswith("//", i):
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        elif text.startswith("/*", i):
            i = text.index("*/", i) + 2
            continue
        else:
            out.append(c)
        i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def lint_config() -> list[str]:
    problems = []
    try:
        data = json.loads(strip_jsonc((REPO / "config/config.example.json").read_text(encoding="utf-8")))
        schema = json.loads((REPO / "config/config.schema.json").read_text(encoding="utf-8"))
    except (ValueError, OSError) as e:
        return [f"config: CFG001 {e}"]
    try:
        import jsonschema
    except ImportError:
        print("note: jsonschema not installed; skipping schema validation (pip install jsonschema)")
        return problems
    for err in jsonschema.Draft202012Validator(schema).iter_errors(data):
        problems.append(f"config/config.example.json: CFG001 {'/'.join(map(str, err.path))}: {err.message}")
    return problems


def main(argv: list[str]) -> int:
    terms = private_terms()
    problems: list[str] = []
    files = tracked_files()
    for f in files:
        problems += lint_file(f, terms)
    problems += lint_tests()
    problems += lint_config()
    for p in problems:
        print(p)
    print(f"lint: {len(files)} files, {len(problems)} problem(s)" + ("" if terms else " (no private-term list loaded)"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
