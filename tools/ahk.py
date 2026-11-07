"""Shared helpers for running AutoHotkey v2 from Python on Windows or under Wine.

Configuration (environment):
  AHK_EXE      path to AutoHotkey64.exe (default on Windows: AutoHotkey64.exe on PATH, then
               the per-user and machine-wide installs; /opt/ahk/AutoHotkey64.exe elsewhere)
  AHK_WRAPPER  command prefix used off Windows (default: "xvfb-run -a wine")
"""
from __future__ import annotations

import os
import shlex
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IS_WINDOWS = sys.platform == "win32"


def ahk_exe() -> str:
    if os.environ.get("AHK_EXE"):
        return os.environ["AHK_EXE"]
    if not IS_WINDOWS:
        return "/opt/ahk/AutoHotkey64.exe"
    if shutil.which("AutoHotkey64.exe"):
        return "AutoHotkey64.exe"
    # The AutoHotkey v2 installer does not add itself to PATH.
    for root in (os.environ.get("LOCALAPPDATA", "") + r"\Programs", os.environ.get("ProgramFiles", "")):
        candidate = Path(root, "AutoHotkey", "v2", "AutoHotkey64.exe")
        if root and candidate.is_file():
            return str(candidate)
    return "AutoHotkey64.exe"


def to_ahk_path(path: Path | str) -> str:
    """Converts a host path into one AutoHotkey can open (Z:\\... under Wine)."""
    p = Path(path).resolve()
    if IS_WINDOWS:
        return str(p)
    return "Z:" + str(p).replace("/", "\\")


@dataclass
class Result:
    code: int
    out: str
    timed_out: bool = False


def run(script: Path | str, *args: str, timeout: int = 120, env: dict | None = None) -> Result:
    """Runs an AutoHotkey script headlessly and captures stdout."""
    cmd = [] if IS_WINDOWS else shlex.split(os.environ.get("AHK_WRAPPER", "xvfb-run -a wine"))
    cmd += [ahk_exe(), "/ErrorStdOut", to_ahk_path(script), *args]
    full_env = dict(os.environ)
    full_env.update({"HOTKIT_HEADLESS": "1", "WINEDEBUG": "-all"})
    if env:
        full_env.update(env)
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=timeout, env=full_env)
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode("utf-8", "replace")
        _kill_wine()
        return Result(124, out, timed_out=True)
    out = proc.stdout.decode("utf-8", "replace") + proc.stderr.decode("utf-8", "replace")
    noise = ("X connection to", "syswow64\\rundll32", "configuration in L", "wine: ")
    out = "\n".join(line for line in out.splitlines() if not line.startswith(noise))
    return Result(proc.returncode, out.lstrip("\ufeff"))


def validate(script: Path | str) -> Result:
    """Loads a script with /Validate: syntax and #Include errors, no execution."""
    cmd = [] if IS_WINDOWS else shlex.split(os.environ.get("AHK_WRAPPER", "xvfb-run -a wine"))
    cmd += [ahk_exe(), "/ErrorStdOut", "/Validate", to_ahk_path(script)]
    env = dict(os.environ, WINEDEBUG="-all")
    proc = subprocess.run(cmd, capture_output=True, timeout=120, env=env)
    out = proc.stdout.decode("utf-8", "replace") + proc.stderr.decode("utf-8", "replace")
    out = "\n".join(l for l in out.splitlines() if "X connection to" not in l and "rundll32" not in l
                    and "configuration in L" not in l)
    return Result(proc.returncode, out)


def _kill_wine() -> None:
    if not IS_WINDOWS:
        subprocess.run(["wineserver", "-k"], capture_output=True)
