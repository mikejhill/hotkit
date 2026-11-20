#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\SimulatedKeys.ahk

; Remote sessions: windows of clients that forward keys to another machine
; (Remote Desktop, VNC viewers). Local bindings keep working there, and keys that no
; local binding takes reach the remote machine.
;
; While one of the listed windows is active:
;   - hotkit keeps its keyboard hook ahead of the client's. The newest low-level
;     hook sees keys first, and Remote Desktop installs one whenever its window
;     or its input area gets focus, so hotkit re-installs its own just after
;     activation and then every second. A forced re-install also clears key
;     state the client swallowed, such as the release of the CapsLock that
;     switched to it. A re-install waits while a key pressed since activation is
;     still held (as our own hook saw it), since it would forget that key; after
;     10 seconds it goes ahead, in case the client swallowed the release.
;   - A held modifier with a remoteKey (e.g. CapsLock -> F18) is passed on as
;     that key: pressing the modifier presses remoteKey in the session, and
;     releasing it releases remoteKey. The remote hotkit, with the same
;     modifier config, treats remoteKey as the modifier, so its bindings fire
;     on combinations no local binding takes. The modifier itself never reaches
;     the session, so a forced CapsLock state stays in force on both machines.
;   - Before a local modifier binding runs, remoteKey is released in the
;     session, so the remote machine doesn't see the modifier stuck down.
;   - Bindings marked yieldToRemote stand aside.
class RemoteSessions {
    static titles := []
    ; [{ key, remoteKey, vk, state: { pressed, released }, sent }]: pressed is the
    ; physical press cycle, released means a local binding (or leaving the
    ; window) let go of remoteKey until that press ends, and sent is what the
    ; session was last told.
    static modifiers := []
    static active := false
    static ReassertDelays := [50, 300]
    static IntervalMs := 1000
    static MaxHoldMs := 10000
    static _hook := 0
    static _callback := 0
    static _generation := 0        ; bumped on each activation; stale checks stop
    static _heldSince := 0         ; A_TickCount when a check first found keys held
    static _tickFn := ""
    static _window := 0            ; the session window keys are passed on to
    static _owed := Map()          ; hwnd -> [remoteKey]: releases owed to a window

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

    ; Pure: whether a hook re-install must wait. Our hook sits ahead of
    ; AutoHotkey's, so keys it saw go down since activation and not up are
    ; really held, unless they have been "held" for longer than maxHoldMs.
    static MustWait(hookEnabled, heldCount, heldMs := 0, maxHoldMs := 10000)
        => hookEnabled && heldCount > 0 && heldMs < maxHoldMs

    ; Pure: the next forwarding state of a modifier after an event: "down" or
    ; "up" (typed; repeats arrive as "down"), or "release" (a local binding
    ; ran, or focus left the session). remoteKey should be held in the session
    ; exactly while ShouldHold(state).
    static Next(state, event, sessionActive) {
        switch event {
            case "down":
                if state.pressed
                    return state                      ; auto-repeat
                return { pressed: true, released: !sessionActive }
            case "up":
                return { pressed: false, released: false }
            case "release":
                return { pressed: state.pressed, released: true }
        }
        return state
    }

    static ShouldHold(state) => state.pressed && !state.released

    ; modifiers: [{ key, remoteKey }]; entries without remoteKey are ignored.
    static Start(titles, modifiers := []) {
        RemoteSessions.titles := titles
        RemoteSessions.modifiers := []
        for m in modifiers {
            vk := 0
            try vk := GetKeyVK(m.key)
            if (m.remoteKey != "" && vk)
                RemoteSessions.modifiers.Push({ key: m.key, remoteKey: m.remoteKey, vk: vk,
                    state: { pressed: false, released: false }, sent: false })
        }
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
        if RemoteSessions.modifiers.Length {
            SimulatedKeys.OnTyped := (vk, up) => RemoteSessions._OnTyped(vk, up)
            ; A restart or exit must not leave a stand-in held in the session.
            OnExit((*) => RemoteSessions._ReleaseHeld())
        }
        RemoteSessions._tickFn := () => RemoteSessions._Reassert(RemoteSessions._generation)
        RemoteSessions._Update()
    }

    ; True when a remote session window is active. Cheap enough for #HotIf.
    static IsActive() {
        for title in RemoteSessions.titles
            if WinActive(title)
                return true
        return false
    }

    ; Releases a modifier's remoteKey in the session before a local binding
    ; runs; it stays released until the modifier is pressed again.
    static ReleaseKey(key) {
        for m in RemoteSessions.modifiers {
            if (m.key = key) {
                m.state := RemoteSessions.Next(m.state, "release", true)
                RemoteSessions._Sync(m)
            }
        }
    }

    ; Runs inside the SimulatedKeys hook for typed keys. remoteKey is sent from
    ; right here, so it is queued behind this event and ahead of the next key
    ; of the chord (as AutoHotkey's own hook does for its disguise keys).
    static _OnTyped(vk, up) {
        for m in RemoteSessions.modifiers {
            if (vk != m.vk)                   ; Bindings only accepts keys with their own code
                continue
            m.state := RemoteSessions.Next(m.state, up ? "up" : "down", up || RemoteSessions.IsActive())
            RemoteSessions._Sync(m)
        }
    }

    ; Brings the session in line with the state; a no-op when it already is.
    static _Sync(m) {
        hold := RemoteSessions.ShouldHold(m.state)
        if (hold = m.sent)
            return
        m.sent := hold
        RemoteSessions._KeyEvent(m.remoteKey, hold)
    }

    ; A plain keybd_event rather than Send: it is safe inside the hook, and it
    ; carries the scan code that Remote Desktop forwards.
    static _KeyEvent(key, down) {
        try {
            vk := GetKeyVK(key)
            sc := GetKeySC(key)
            flags := (down ? 0 : 0x2) | (sc > 0xFF ? 0x1 : 0)  ; KEYEVENTF_KEYUP, KEYEVENTF_EXTENDEDKEY
            DllCall("keybd_event", "uchar", vk, "uchar", sc & 0xFF, "uint", flags, "uptr", 0)
        }
    }

    static _OnForeground() {
        ; Return from the hook callback at once; the work runs on a timer.
        SetTimer(() => RemoteSessions._Update(), -1)
    }

    static _Update() {
        now := RemoteSessions.IsActive()
        window := now ? WinExist("A") : 0
        ; Moving between two session windows: what the old one holds is let go,
        ; and the new one gets keys from the next press on.
        if (RemoteSessions.active && window != RemoteSessions._window)
            RemoteSessions._ReleaseAll(RemoteSessions._window)
        RemoteSessions._window := window
        if (now)
            RemoteSessions._PayOwed(window)
        if (now) {
            generation := ++RemoteSessions._generation
            RemoteSessions._heldSince := 0
            ; Presses from before activation may have lost their release to the client.
            SimulatedKeys.down.Clear()
            ; One closure per delay: SetTimer on the same function would just move one timer.
            for delay in RemoteSessions.ReassertDelays
                SetTimer(RemoteSessions._ReassertLater(generation), -delay)
        }
        if (now = RemoteSessions.active)
            return
        RemoteSessions.active := now
        SetTimer(RemoteSessions._tickFn, now ? RemoteSessions.IntervalMs : 0)
    }

    ; Focus already left the window. The release is sent now anyway, which
    ; clears the key's state here, and is also owed to the window and sent
    ; again when it is active next, for clients that keep keys held while
    ; unfocused (most let go of them on losing focus).
    static _ReleaseAll(window) {
        for m in RemoteSessions.modifiers {
            wasSent := m.sent
            m.state := RemoteSessions.Next(m.state, "release", false)
            RemoteSessions._Sync(m)
            if (wasSent && window) {
                if !RemoteSessions._owed.Has(window)
                    RemoteSessions._owed[window] := []
                RemoteSessions._owed[window].Push(m.remoteKey)
            }
        }
    }

    static _ReleaseHeld() {
        for m in RemoteSessions.modifiers {
            if m.sent
                RemoteSessions._KeyEvent(m.remoteKey, false)
            m.sent := false
        }
    }

    static _PayOwed(window) {
        if RemoteSessions._owed.Has(window) {
            for key in RemoteSessions._owed[window]
                RemoteSessions._KeyEvent(key, false)
            RemoteSessions._owed.Delete(window)
        }
        stale := []
        for hwnd in RemoteSessions._owed
            if !WinExist("ahk_id " hwnd)
                stale.Push(hwnd)
        for hwnd in stale
            RemoteSessions._owed.Delete(hwnd)
    }

    static _ReassertLater(generation) => (*) => RemoteSessions._Reassert(generation)

    ; Re-installs AutoHotkey's keyboard hook (resetting its key state) so it runs
    ; ahead of the client's, then ours ahead of that, as at startup.
    static _Reassert(generation) {
        if (generation != RemoteSessions._generation || !RemoteSessions.IsActive())
            return
        now := A_TickCount
        held := SimulatedKeys.down.Count
        ; The deadline runs from when keys were last all up, not the first check.
        if (held && (!RemoteSessions._heldSince || SimulatedKeys.emptyAt > RemoteSessions._heldSince))
            RemoteSessions._heldSince := now
        heldMs := held ? now - RemoteSessions._heldSince : 0
        if RemoteSessions.MustWait(SimulatedKeys.enabled, held, heldMs, RemoteSessions.MaxHoldMs)
            return
        RemoteSessions._heldSince := 0
        SimulatedKeys.down.Clear()
        ; Forget presses too, as AutoHotkey is about to: release a stand-in
        ; left down by a release the client swallowed.
        for m in RemoteSessions.modifiers {
            m.state := RemoteSessions.Next(m.state, "up", false)
            RemoteSessions._Sync(m)
        }
        try InstallKeybdHook(true, true)
        if SimulatedKeys.enabled
            try SimulatedKeys._Install()
    }
}
