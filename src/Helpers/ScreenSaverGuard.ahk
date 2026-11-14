#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, OutputDebug

; Turns the screen saver back on when hotkit stops pausing it, including when
; hotkit is killed or crashes. Windows keeps a SystemParametersInfo change for
; the rest of the sign-in session, so without this a crash during Keep
; Unlocked would leave the screen saver (and its lock) off until sign-out.
;
; PowerModule starts this while it pauses the screen saver and holds a named
; mutex for as long as the pause lasts. The guard waits for that mutex: it is
; released when hotkit restores the screen saver itself, and abandoned when
; hotkit's process ends without doing so. Either way the guard turns the screen
; saver on, removes the pause marker and exits.
;
; Usage: AutoHotkey64.exe ScreenSaverGuard.ahk <mutex name> [<marker file> [<ready event>]]
; The ready event (named, created by hotkit) is signaled once the guard holds
; its mutex handle; hotkit doesn't pause the screen saver before that.
; HOTKIT_GUARD_DRY_RUN=<file> appends "restored" to that file instead of
; changing the screen saver (tests).

OnError((*) => ExitApp(2))

if (A_Args.Length < 1)
    ExitApp(2)
mutexName := A_Args[1]
marker := A_Args.Length >= 2 ? A_Args[2] : ""
readyEvent := A_Args.Length >= 3 ? A_Args[3] : ""

SYNCHRONIZE := 0x00100000
EVENT_MODIFY_STATE := 0x0002
h := DllCall("OpenMutexW", "UInt", SYNCHRONIZE, "Int", 0, "Str", mutexName, "Ptr")
if (!h)
    ExitApp(1) ; Already gone: hotkit restored and closed it before we started.
if (readyEvent != "") {
    ev := DllCall("OpenEventW", "UInt", EVENT_MODIFY_STATE, "Int", 0, "Str", readyEvent, "Ptr")
    if (ev) {
        DllCall("SetEvent", "Ptr", ev)
        DllCall("CloseHandle", "Ptr", ev)
    }
}

result := DllCall("WaitForSingleObject", "Ptr", h, "UInt", 0xFFFFFFFF, "UInt")
if (result = 0 || result = 0x80) { ; WAIT_OBJECT_0, WAIT_ABANDONED
    dryRun := EnvGet("HOTKIT_GUARD_DRY_RUN")
    if (dryRun != "")
        FileAppend("restored`n", dryRun)
    else
        DllCall("SystemParametersInfoW", "UInt", 0x11, "UInt", 1, "Ptr", 0, "UInt", 0) ; SPI_SETSCREENSAVEACTIVE
    if (marker != "")
        try FileDelete(marker)
    DllCall("ReleaseMutex", "Ptr", h)
}
DllCall("CloseHandle", "Ptr", h)
ExitApp(0)
