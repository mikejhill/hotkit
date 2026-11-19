#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\SimulatedKeys.ahk

; Remote sessions: windows of clients that forward keys to another machine
; (Remote Desktop, VNC viewers). Local bindings keep working there, and keys that no
; local binding takes reach the remote machine, CapsLock combinations included.
;
; While one of the listed windows is active:
;   - Shortly after it is activated, hotkit re-installs its keyboard hook. The
;     newest low-level hook sees keys first, and Remote Desktop installs one when
;     its window gets focus. Re-installing also clears key state that the client
;     swallowed, such as the release of the CapsLock that switched to it.
;   - A forced CapsLock state (AlwaysOff/AlwaysOn) is lifted, because a forced
;     state swallows CapsLock and the remote machine never sees it held. The
;     local state is put back when it drifts, and the force when focus leaves.
;   - Before a local modifier binding runs, the modifier key is released in the
;     session, so the remote machine doesn't see it stuck down.
;   - Bindings marked yieldToRemote stand aside.
class RemoteSessions {
    static titles := []
    static capsLock := ""          ; forced state from settings.keyboard.capsLock
    static active := false
    static ReassertDelays := [50, 300, 1000]
    static KeepLockMs := 250
    static _hook := 0
    static _callback := 0
    static _restore := ""          ; force to put back on leaving, or ""
    static _keepTimer := ""

    ; Pure: validates settings.remoteWindows. Returns { titles, problems }.
    static Parse(raw) {
        result := { titles: [], problems: [] }
        if (raw = "")
            return result
        for title in (raw is Array ? raw : [raw]) {
            if (title is String && Trim(title) != "")
                result.titles.Push(title)
            else
                result.problems.Push("settings.remoteWindows: entries must be non-empty WinTitle strings.")
        }
        return result
    }

    ; Pure: the unforced CapsLock state to use inside a session, given the
    ; configured force and whether CapsLock is on now; "" when nothing is forced.
    static LiftedState(forced, toggledOn) {
        if (forced != "AlwaysOff" && forced != "AlwaysOn")
            return ""
        return toggledOn ? "On" : "Off"
    }

    static Start(titles, capsLock := "") {
        RemoteSessions.titles := titles
        RemoteSessions.capsLock := capsLock
        if (!titles.Length || RemoteSessions._hook)
            return
        ; EVENT_SYSTEM_FOREGROUND, out of context: delivered through this thread's message loop.
        RemoteSessions._callback := CallbackCreate((args*) => RemoteSessions._OnForeground(), "F", 7)
        RemoteSessions._hook := DllCall("SetWinEventHook", "uint", 3, "uint", 3, "ptr", 0,
            "ptr", RemoteSessions._callback, "uint", 0, "uint", 0, "uint", 0, "ptr")
        if !RemoteSessions._hook {
            CallbackFree(RemoteSessions._callback)
            RemoteSessions._callback := 0
            throw OSError(A_LastError, , "SetWinEventHook")
        }
        RemoteSessions._Update()
    }

    ; True when a remote session window is active. Cheap enough for #HotIf.
    static IsActive() {
        for title in RemoteSessions.titles
            if WinActive(title)
                return true
        return false
    }

    ; Releases a held modifier key in the session before a local binding runs.
    static ReleaseKey(key) {
        if (key != "" && RemoteSessions.titles.Length && RemoteSessions.IsActive())
            try Send("{Blind}{" key " up}")
    }

    static _OnForeground() {
        ; Return from the hook callback at once; the work runs on a timer.
        SetTimer(() => RemoteSessions._Update(), -1)
    }

    static _Update() {
        now := RemoteSessions.IsActive()
        if (now) {
            for delay in RemoteSessions.ReassertDelays
                SetTimer(() => RemoteSessions._Reassert(), -delay)
        }
        if (now = RemoteSessions.active)
            return
        RemoteSessions.active := now
        if (now)
            RemoteSessions._LiftCapsLock()
        else
            RemoteSessions._RestoreCapsLock()
    }

    ; Re-installs AutoHotkey's keyboard hook (resetting its key state) so it runs
    ; ahead of the client's, then ours ahead of that, as at startup.
    static _Reassert() {
        if !RemoteSessions.IsActive()
            return
        try InstallKeybdHook(true, true)
        if SimulatedKeys.enabled
            try SimulatedKeys._Install()
    }

    static _LiftCapsLock() {
        lifted := RemoteSessions.LiftedState(RemoteSessions.capsLock, GetKeyState("CapsLock", "T"))
        if (lifted = "")
            return
        ; Put back the force that matches the current state, which keyboard.toggleCapsLock may have flipped.
        RemoteSessions._restore := lifted = "On" ? "AlwaysOn" : "AlwaysOff"
        SetCapsLockState(lifted)
        RemoteSessions._keepTimer := () => RemoteSessions._KeepCapsLock(lifted = "On")
        SetTimer(RemoteSessions._keepTimer, RemoteSessions.KeepLockMs)
    }

    ; CapsLock now reaches the system too; undo a local toggle once it's released.
    static _KeepCapsLock(wantOn) {
        if (GetKeyState("CapsLock", "T") != wantOn && !GetKeyState("CapsLock", "P"))
            SetCapsLockState(wantOn ? "On" : "Off")
    }

    static _RestoreCapsLock() {
        if (RemoteSessions._keepTimer != "")
            SetTimer(RemoteSessions._keepTimer, 0)
        RemoteSessions._keepTimer := ""
        if (RemoteSessions._restore != "")
            SetCapsLockState(RemoteSessions._restore)
        RemoteSessions._restore := ""
    }
}
