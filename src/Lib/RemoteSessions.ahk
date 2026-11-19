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
;     swallowed, such as the release of the CapsLock that switched to it. A check
;     is skipped when our own hook saw a key since the previous one: hotkit is
;     still first then, and re-installing would forget keys held right now.
;   - A forced CapsLock state (AlwaysOff/AlwaysOn) is lifted, because a forced
;     state swallows CapsLock and the remote machine never sees it held. The
;     force comes back when focus leaves. The local state isn't corrected in
;     between: that takes a CapsLock keystroke, which the client would forward.
;   - Before a local modifier binding runs, the modifier key is released in the
;     session, so the remote machine doesn't see it stuck down.
;   - Bindings marked yieldToRemote stand aside.
class RemoteSessions {
    static titles := []
    static capsLock := ""          ; forced state from settings.keyboard.capsLock
    static active := false
    static ReassertDelays := [50, 300, 1000]
    static _hook := 0
    static _callback := 0
    static _restore := ""          ; force to put back on leaving, or ""
    static _checkedAt := 0         ; A_TickCount of the last hook check

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

    ; Pure: whether a hook check may be skipped because our hook, which sits
    ; ahead of AutoHotkey's, recorded a key event after the previous check.
    ; Tick arithmetic wraps like GetTickCount.
    static SawKeySince(hookEnabled, eventTime, sinceTick) {
        return hookEnabled && eventTime != 0 && ((eventTime - sinceTick) & 0xFFFFFFFF) < 0x80000000
    }

    ; keyboard.toggleCapsLock forced a state inside a session: keep it when leaving.
    static CapsLockForced(state) {
        if (RemoteSessions.active && RemoteSessions._restore != "")
            RemoteSessions._restore := state
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
            RemoteSessions._checkedAt := A_TickCount & 0xFFFFFFFF
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
        since := RemoteSessions._checkedAt
        RemoteSessions._checkedAt := A_TickCount & 0xFFFFFFFF
        if RemoteSessions.SawKeySince(SimulatedKeys.enabled, SimulatedKeys.last.time, since)
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
    }

    static _RestoreCapsLock() {
        if (RemoteSessions._restore != "")
            SetCapsLockState(RemoteSessions._restore)
        RemoteSessions._restore := ""
    }
}
