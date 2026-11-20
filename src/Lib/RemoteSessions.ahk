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
    static modifiers := []         ; [{ key, remoteKey, vk }]
    static active := false
    static ReassertDelays := [50, 300]
    static IntervalMs := 1000
    static MaxHoldMs := 10000
    static _hook := 0
    static _callback := 0
    static _generation := 0        ; bumped on each activation; stale checks stop
    static _heldSince := 0         ; A_TickCount when a check first found keys held
    static _tickFn := ""
    static _forwarded := Map()     ; remoteKey -> true while pressed in the session

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

    ; Pure: what a typed modifier event does in a remote session: "down" to
    ; press remoteKey there, "up" to release it, or "" to do nothing.
    static ForwardAction(up, forwarded, sessionActive) {
        if up
            return forwarded ? "up" : ""
        return (!forwarded && sessionActive) ? "down" : ""
    }

    ; modifiers: [{ key, remoteKey }]; entries without remoteKey are ignored.
    static Start(titles, modifiers := []) {
        RemoteSessions.titles := titles
        RemoteSessions.modifiers := []
        for m in modifiers {
            vk := 0
            try vk := GetKeyVK(m.key)
            if (m.remoteKey != "" && vk)
                RemoteSessions.modifiers.Push({ key: m.key, remoteKey: m.remoteKey, vk: vk })
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
        if RemoteSessions.modifiers.Length
            SimulatedKeys.OnTyped := (vk, up) => RemoteSessions._OnTyped(vk, up)
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

    ; Releases a modifier's remoteKey in the session before a local binding runs.
    static ReleaseKey(key) {
        for m in RemoteSessions.modifiers {
            if (m.key = key && RemoteSessions._forwarded.Has(m.remoteKey)) {
                RemoteSessions._forwarded.Delete(m.remoteKey)
                RemoteSessions._Send(m.remoteKey, false)
            }
        }
    }

    ; Runs inside the SimulatedKeys hook for typed keys: decide now, send later.
    static _OnTyped(vk, up) {
        for m in RemoteSessions.modifiers {
            if (m.vk != vk)
                continue
            forwarded := RemoteSessions._forwarded.Has(m.remoteKey)
            switch RemoteSessions.ForwardAction(up, forwarded, forwarded || RemoteSessions.IsActive()) {
                case "down":
                    RemoteSessions._forwarded[m.remoteKey] := true
                    SetTimer(RemoteSessions._SendLater(m.remoteKey, true), -1)
                case "up":
                    RemoteSessions._forwarded.Delete(m.remoteKey)
                    SetTimer(RemoteSessions._SendLater(m.remoteKey, false), -1)
            }
        }
    }

    static _SendLater(key, down) => (*) => RemoteSessions._Send(key, down)

    static _Send(key, down) {
        try Send("{Blind}{" key (down ? " down" : " up") "}")
    }

    static _OnForeground() {
        ; Return from the hook callback at once; the work runs on a timer.
        SetTimer(() => RemoteSessions._Update(), -1)
    }

    static _Update() {
        now := RemoteSessions.IsActive()
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
        if (!now) {
            for key in RemoteSessions._ForwardedKeys()
                RemoteSessions._Send(key, false)
            RemoteSessions._forwarded := Map()
        }
    }

    static _ForwardedKeys() {
        keys := []
        for key in RemoteSessions._forwarded
            keys.Push(key)
        return keys
    }

    static _ReassertLater(generation) => (*) => RemoteSessions._Reassert(generation)

    ; Re-installs AutoHotkey's keyboard hook (resetting its key state) so it runs
    ; ahead of the client's, then ours ahead of that, as at startup.
    static _Reassert(generation) {
        if (generation != RemoteSessions._generation || !RemoteSessions.IsActive())
            return
        now := A_TickCount
        held := SimulatedKeys.down.Count
        if (held && !RemoteSessions._heldSince)
            RemoteSessions._heldSince := now
        heldMs := held ? now - RemoteSessions._heldSince : 0
        if RemoteSessions.MustWait(SimulatedKeys.enabled, held, heldMs, RemoteSessions.MaxHoldMs)
            return
        RemoteSessions._heldSince := 0
        SimulatedKeys.down.Clear()
        try InstallKeybdHook(true, true)
        if SimulatedKeys.enabled
            try SimulatedKeys._Install()
    }
}
