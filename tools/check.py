#!/usr/bin/env python3
"""Checks your real hotkit setup and reports what the running app logged.

  python tools/check.py                    sync the plugin stub, --check config.json + plugins
  python tools/check.py --config FILE      check FILE instead (e.g. an edited copy before swapping it in)
  python tools/check.py --no-log           skip the running app's status log

Prints the --check report, then any WARN/ERROR lines from the latest run in
<config dir>\\hotkit.log (load failures, skipped reloads, unhandled errors that
the running app showed as a dialog or toast). Exit status: the --check code
(0 ok, 1 problems, 2 config not loadable, 3 script error), or 4 when the check
passed but the latest run logged an ERROR.

Run this after every edit to config.json or a plugin. Never start the app
itself from an automated shell; this only runs the non-interactive modes.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ahk  # noqa: E402

MAIN = ahk.REPO / "src" / "Main.ahk"


def config_dir() -> Path:
    """Mirrors Paths.ConfigDir() without the --config-dir override."""
    if os.environ.get("HOTKIT_CONFIG_DIR"):
        return Path(os.path.expandvars(os.environ["HOTKIT_CONFIG_DIR"]))
    if os.environ.get("XDG_CONFIG_HOME"):
        return Path(os.environ["XDG_CONFIG_HOME"]) / "hotkit"
    return Path(os.environ.get("USERPROFILE", Path.home())) / ".config" / "hotkit"


def latest_run(log: Path) -> list[str]:
    """Lines of the newest run (from its last 'started' line on)."""
    if not log.is_file():
        return []
    lines = log.read_text(encoding="utf-8-sig", errors="replace").splitlines()
    start = 0
    for i, line in enumerate(lines):
        if "[INFO] started " in line:
            start = i
    return lines[start:]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", help="config file to check instead of <config dir>\\config.json")
    parser.add_argument("--no-log", action="store_true", help="do not read the running app's status log")
    args = parser.parse_args(argv)

    extra = ["--config", ahk.to_ahk_path(args.config)] if args.config else []
    sync = ahk.run(MAIN, "--sync-plugins", *extra)
    if sync.code != 0:
        print(sync.out.rstrip())
        print("sync-plugins failed")
        return sync.code or 1
    check = ahk.run(MAIN, "--check", *extra)
    print(check.out.rstrip())
    if check.timed_out:
        print("check timed out")
    code = check.code

    if not args.no_log:
        log = config_dir() / "hotkit.log"
        run = latest_run(log)
        notable = [line for line in run if "[WARN]" in line or "[ERROR]" in line]
        if run:
            print(f"\nrunning app ({log}), latest run: {run[0].split(' [', 1)[0]}")
            for line in notable:
                print("  " + line)
            if not notable:
                print("  no warnings or errors")
        if code == 0 and any("[ERROR]" in line for line in run):
            code = 4
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
