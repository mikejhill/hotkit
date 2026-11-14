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
import tempfile
import time
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


# Exit code when a run was stopped because the script opened a dialog.
DIALOG_EXIT = 125


def run(script: Path | str, *args: str, timeout: int = 120, env: dict | None = None) -> Result:
    """Runs an AutoHotkey script headlessly and captures stdout and stderr.

    On Windows, a dialog the script opens (an AutoHotkey warning or error
    window, or a MsgBox) is read, closed by ending the script, and reported
    in the output as "dialog: <title>: <text>" with exit code DIALOG_EXIT, so
    an automated run never leaves a window waiting on someone's desktop.
    """
    cmd = [] if IS_WINDOWS else shlex.split(os.environ.get("AHK_WRAPPER", "xvfb-run -a wine"))
    cmd += [ahk_exe(), "/ErrorStdOut", to_ahk_path(script), *args]
    full_env = dict(os.environ)
    full_env.update({"HOTKIT_HEADLESS": "1", "WINEDEBUG": "-all"})
    if env:
        full_env.update(env)
    with tempfile.TemporaryFile() as out_file:
        proc = subprocess.Popen(cmd, stdout=out_file, stderr=subprocess.STDOUT, env=full_env)
        code, dialogs, timed_out = _wait(proc, timeout)
        out_file.seek(0)
        out = out_file.read().decode("utf-8", "replace")
    if timed_out:
        _kill_wine()
    noise = ("X connection to", "syswow64\\rundll32", "configuration in L", "wine: ")
    out = "\n".join(line for line in out.splitlines() if not line.startswith(noise)).lstrip("\ufeff")
    for d in dialogs:
        out += ("\n" if out else "") + "dialog: " + d
    if dialogs:
        return Result(DIALOG_EXIT, out)
    return Result(124 if timed_out else code, out, timed_out=timed_out)


def _wait(proc: subprocess.Popen, timeout: float) -> tuple[int, list[str], bool]:
    """Waits for proc; returns (exit code, dialog texts, timed out)."""
    deadline = time.monotonic() + timeout
    while True:
        try:
            return proc.wait(timeout=0.2), [], False
        except subprocess.TimeoutExpired:
            pass
        dialogs = dialog_texts(proc.pid) if IS_WINDOWS else []
        if dialogs or time.monotonic() >= deadline:
            proc.kill()
            proc.wait()
            return proc.returncode, dialogs, not dialogs


def dialog_texts(pid: int) -> list[str]:
    """Visible standard dialogs (#32770) owned by pid, as "title: text" (Windows only)."""
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.WinDLL("user32", use_last_error=True)
    proc_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def text(hwnd: int) -> str:
        # WM_GETTEXT reads controls in another process (GetWindowText doesn't).
        buf = ctypes.create_unicode_buffer(8192)
        result = ctypes.c_size_t()
        user32.SendMessageTimeoutW(hwnd, 0x000D, len(buf), buf, 0x0002, 1000, ctypes.byref(result))
        return buf.value

    def cls(hwnd: int) -> str:
        buf = ctypes.create_unicode_buffer(256)
        user32.GetClassNameW(hwnd, buf, 256)
        return buf.value

    found: list[str] = []

    def on_window(hwnd: int, _: int) -> bool:
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value != pid or not user32.IsWindowVisible(hwnd) or cls(hwnd) != "#32770":
            return True
        parts: list[str] = []

        def on_child(child: int, _: int) -> bool:
            if cls(child) != "Button":
                t = text(child).strip()
                if t:
                    parts.append(" ".join(t.replace("Show call stack »", "").split()))
            return True

        user32.EnumChildWindows(hwnd, proc_type(on_child), 0)
        found.append(f"{text(hwnd)}: " + " | ".join(parts))
        return True

    user32.EnumWindows(proc_type(on_window), 0)
    return found


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
