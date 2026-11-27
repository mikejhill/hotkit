#Requires AutoHotkey v2.0

; Windows that get the keyboard to themselves. While one of the WinTitles in
; settings.suspendWhenActive is active, hotkit suspends every shortcut
; (layer keys included) and lifts a forced CapsLock, NumLock, or ScrollLock
; state, so that window sees those keys as typed. Typical use: a remote
; session client whose machine runs its own hotkit with the same keys.
; Focusing any other window brings everything back.
class SuspendWindows {
    static titles := []
    ; Lock key name -> configured state, e.g. "CapsLock" -> "AlwaysOff".
    static locks := Map()
    ; Whether the shortcuts are suspended because of a listed window.
    static active := false
    ; Whether the shortcuts were already suspended (tray) when a listed window took over.
    static _wasSuspended := false
    ; Called on entry to end holds and latches whose release or next key
    ; would otherwise go unseen (set by App).
    static EndPending := ""
    static OnChange := ""
    static _hook := 0
    static _callback := 0
    static _poll := (*) => SuspendWindows.Update()

    ; Pure: parses settings.suspendWhenActive (a WinTitle or a list of them).
    static Parse(raw) {
        result := { titles: [], problems: [] }
        if (raw is Array && !raw.Length)
            return result
        for title in (raw is Array ? raw : [raw]) {
            if (title is String && Trim(title) != "")
                result.titles.Push(title)
            else
                result.problems.Push("settings.suspendWhenActive: entries must be non-empty WinTitle strings.")
        }
        return result
    }

    ; Pure: lock keys whose configured state is forced (AlwaysOn/AlwaysOff).
    static ForcedLocks(states) {
        out := Map()
        for name, state in states {
            if (state is String && InStr(state, "Always") = 1)
                out[name] := state
        }
        return out
    }

    ; With keepLocks, forced lock states also hold while suspended: the keys
    ; still reach the window, and a toggle they cause here is set back once
    ; the key is released (see _KeepLocks).
    static keepLocks := false
    static _keep := (*) => SuspendWindows._KeepLocks()

    static Start(titles, locks := Map(), keepLocks := false) {
        SuspendWindows.titles := titles
        SuspendWindows.locks := SuspendWindows.ForcedLocks(locks)
        SuspendWindows.keepLocks := keepLocks
        if (!titles.Length || SuspendWindows._hook)
            return
        ; EVENT_SYSTEM_FOREGROUND, out of context: delivered through this thread's message loop.
        SuspendWindows._callback := CallbackCreate((args*) => SuspendWindows.Update(), "F", 7)
        SuspendWindows._hook := DllCall("SetWinEventHook", "uint", 3, "uint", 3, "ptr", 0,
            "ptr", SuspendWindows._callback, "uint", 0, "uint", 0, "uint", 0, "ptr")
        if !SuspendWindows._hook {
            CallbackFree(SuspendWindows._callback)
            SuspendWindows._callback := 0
            throw OSError(A_LastError, , "SetWinEventHook")
        }
        ; Foreground events can be missed (elevated windows, a busy thread).
        SetTimer(SuspendWindows._poll, 500)
        OnExit((*) => SuspendWindows._Leave())
        SuspendWindows.Update()
    }

    static Matches() {
        for title in SuspendWindows.titles {
            if WinActive(title)
                return true
        }
        return false
    }

    static Update() {
        want := false
        try want := SuspendWindows.Matches()
        if (want = SuspendWindows.active)
            return
        if want
            SuspendWindows._Enter()
        else
            SuspendWindows._Leave()
    }

    ; Lock keys a toggle action forces at runtime (keyboard.toggleCapsLock)
    ; replace the configured state, so leaving restores the policy in effect.
    static SetForced(name, state) {
        if (state is String && InStr(state, "Always") = 1)
            SuspendWindows.locks[name] := state
    }

    static _Enter() {
        ; Mark the transition first: the actions EndPending runs may take long
        ; enough for the poll to call Update again.
        SuspendWindows.active := true
        SuspendWindows._wasSuspended := A_IsSuspended
        if HasMethod(SuspendWindows.EndPending)
            try SuspendWindows.EndPending.Call()
        Suspend(true)
        if SuspendWindows.keepLocks
            SetTimer(SuspendWindows._keep, 100)
        ; Lift forced states and keep the current one, so the key toggles as usual.
        for name in SuspendWindows.locks
            SuspendWindows._SetLock(name, GetKeyState(name, "T") ? "On" : "Off")
        SuspendWindows._Notify()
    }

    static _Leave() {
        if !SuspendWindows.active
            return
        SuspendWindows.active := false
        SetTimer(SuspendWindows._keep, 0)
        SuspendWindows._Restore()
        ; A remote client may sync its session's lock state back to this
        ; machine after it loses focus, so enforce the policy again shortly.
        for ms in SuspendWindows.ReassertMs
            SetTimer(ObjBindMethod(SuspendWindows, "_Reassert"), -ms)  ; one timer each
        if !SuspendWindows._wasSuspended {
            Suspend(false)
            ; Resuming re-installs AutoHotkey's hook ahead of ours; restore the order.
            SimulatedKeys._Reinstall()
        }
        SuspendWindows._Notify()
    }

    static ReassertMs := [250, 1000, 2500]

    ; While suspended with keepLocks: a forced key toggled by a press in the
    ; window is set back after release. That correction reaches the window
    ; too, as a simulated press of the key.
    static _KeepLocks() {
        if !SuspendWindows.active
            return SetTimer(SuspendWindows._keep, 0)
        modsHeld := false
        for mod in ["Ctrl", "Alt", "Shift", "LWin", "RWin"]
            modsHeld := modsHeld || GetKeyState(mod, "P")
        for name, state in SuspendWindows.locks {
            want := SuspendWindows.ForcedToggle(state)
            toggle := SuspendWindows.ToggleOf(name), held := GetKeyState(name, "P")
            ; A new press, or the toggle back where it belongs, allows new attempts.
            if (held || toggle = want)
                SuspendWindows._attempts[name] := 0
            tries := SuspendWindows._attempts.Has(name) ? SuspendWindows._attempts[name] : 0
            ; Give a correction time to land before trying again, or two could cancel out.
            if (tries && A_TickCount - SuspendWindows._lastAttempt < 600)
                continue
            if SuspendWindows.NeedsCorrection(toggle, want, held, modsHeld, tries) {
                SuspendWindows._attempts[name] := tries + 1
                SuspendWindows._lastAttempt := A_TickCount
                SuspendWindows._SetLock(name, want ? "On" : "Off")
            }
        }
    }

    static _attempts := Map()
    static _lastAttempt := 0
    static MaxCorrections := 3

    ; Pure: whether a lock key's toggle must be set back now: it differs from
    ; the forced side, the key isn't held (it may be a modifier in use), no
    ; Ctrl/Alt/Shift/Win is held (the simulated press would join a shortcut),
    ; and earlier attempts for this mismatch haven't run out (a client may
    ; take the press without the toggle changing here).
    static NeedsCorrection(toggle, want, held, modsHeld := false, tries := 0)
        => toggle != want && !held && !modsHeld && tries < SuspendWindows.MaxCorrections

    static _Reassert() {
        ; Focus may be back on a listed window before Update has seen it.
        matches := true
        try matches := SuspendWindows.Matches()
        if (!SuspendWindows.active && !matches)
            SuspendWindows._Restore()
    }

    ; Applies the forced policy. A key toggled the wrong way is first set to
    ; the forced side, since the toggle can change outside our hook.
    static _Restore() {
        for name, state in SuspendWindows.locks {
            want := SuspendWindows.ForcedToggle(state)
            if (SuspendWindows.ToggleOf(name) != want)
                SuspendWindows._SetLock(name, want ? "On" : "Off")
            SuspendWindows._SetLock(name, state)
        }
    }

    static ToggleOf(name) => GetKeyState(name, "T")

    ; Pure: the toggle state a forced policy keeps (AlwaysOn -> 1, AlwaysOff -> 0).
    static ForcedToggle(state) => state = "AlwaysOn" ? 1 : 0

    static _SetLock(name, state) {
        switch name {
            case "CapsLock": SetCapsLockState(state)
            case "NumLock": SetNumLockState(state)
            case "ScrollLock": SetScrollLockState(state)
        }
    }

    static _Notify() {
        if HasMethod(SuspendWindows.OnChange)
            try SuspendWindows.OnChange.Call(SuspendWindows.active)
    }
}
