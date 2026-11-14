#!/usr/bin/env python3
"""Runs a throwaway AutoHotkey script or snippet headlessly and prints what happened.

  python tools/probe.py SCRIPT.ahk [-- args...]
  python tools/probe.py --code "MsgBox(1)" [--include src/Core/Tray.ahk ...]

Use this instead of starting AutoHotkey directly when trying something out.
The script runs inside a wrapper that sends warnings (#Warn) and unhandled
errors to the output instead of dialogs, and any dialog that still opens (a
MsgBox, for example) is read, closed and reported as "dialog: ...". Nothing is
left on screen. FileAppend(text, "*") prints from the script.

Exit status: the script's own exit code, 124 on timeout, or 125 when a dialog
was closed.
"""
from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ahk  # noqa: E402

PRELUDE = """#Requires AutoHotkey v2.0
#Warn All, StdOut
#NoTrayIcon
#SingleInstance Off
OnError((err, *) => (FileAppend("error: " err.Message " (" err.File ":" err.Line ")`n", "*", "UTF-8"), ExitApp(3)))
"""


def wrapper(target: Path | None, code: str, includes: list[Path]) -> str:
    """Pure: the wrapper script text for a target script or a code snippet."""
    lines = [PRELUDE]
    for inc in includes:
        lines.append(f"#Include {ahk.to_ahk_path(inc)}\n")
    if target is not None:
        lines.append(f"#Include {ahk.to_ahk_path(target)}\n")
    if code:
        lines.append(code.rstrip() + "\n")
    lines.append("ExitApp(0)\n" if code else "")
    return "".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("script", nargs="?", type=Path, help="script to run")
    parser.add_argument("args", nargs="*", help="arguments for the script (put them after -- if they start with -)")
    parser.add_argument("--code", default="", help="AutoHotkey code to run instead of a script")
    parser.add_argument("--include", action="append", type=Path, default=[], help="file to #Include first")
    parser.add_argument("--timeout", type=float, default=60, help="seconds before the script is stopped")
    opts = parser.parse_args(argv)
    if (opts.script is None) == (not opts.code):
        parser.error("give either a script or --code")
    text = wrapper(opts.script.resolve() if opts.script else None, opts.code,
                   [p.resolve() for p in opts.include])
    # A wrapped script keeps its own directory as A_ScriptDir (its relative
    # #Includes and resources depend on it), so the wrapper sits beside it.
    folder = opts.script.resolve().parent if opts.script else Path(tempfile.gettempdir())
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".ahk", prefix=".probe-",
                                     dir=folder, delete=False) as f:
        f.write(text)
        path = Path(f.name)
    try:
        r = ahk.run(path, *opts.args, timeout=opts.timeout)
    finally:
        path.unlink(missing_ok=True)
    if r.out:
        print(r.out)
    if r.timed_out:
        print(f"timed out after {opts.timeout:g} s")
    print(f"exit {r.code}")
    return r.code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
