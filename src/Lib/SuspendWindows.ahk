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
    static OnChange := ""
    static _hook := 0
    static _callback := 0
    static _poll := (*) => SuspendWindows.Update()

    ; Pure: parses settings.suspendWhenActive (a WinTitle or a list of them).
    static Parse(raw) {
        result := { titles: [], problems: [] }
        if (raw = "")
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

    static Start(titles, locks := Map()) {
        SuspendWindows.titles := titles
        SuspendWindows.locks := SuspendWindows.ForcedLocks(locks)
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

    static _Enter() {
        SuspendWindows.active := true
        Suspend(true)
        ; Lift forced states and keep the current one, so the key toggles as usual.
        for name in SuspendWindows.locks
            SuspendWindows._SetLock(name, GetKeyState(name, "T") ? "On" : "Off")
        SuspendWindows._Notify()
    }

    static _Leave() {
        if !SuspendWindows.active
            return
        SuspendWindows.active := false
        for name, state in SuspendWindows.locks
            SuspendWindows._SetLock(name, state)
        Suspend(false)
        SuspendWindows._Notify()
    }

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
