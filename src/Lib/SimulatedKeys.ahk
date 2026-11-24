#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\HotkeyText.ahk

; Tells whether the key event a hotkey is about to fire on was simulated, that
; is, injected by a program (a dictation tool's paste, a remote-access client,
; a mouse utility) rather than typed on a keyboard.
;
; AutoHotkey only ignores keystrokes sent by AutoHotkey scripts; to its
; hotkeys, keys injected by any other program look real. So this installs its
; own low-level keyboard hook. Windows calls the most recently installed hook
; first, so installed after AutoHotkey's (which appears once hotkeys are
; registered), it records each event's LLKHF_INJECTED flag before AutoHotkey
; evaluates its #HotIf callbacks for that event.
;
; Fails open: if the hook isn't running, was skipped (Windows skips a hook
; whose thread is busy) or the recorded event is not the one being checked,
; the key counts as typed. It is re-installed periodically, which keeps it
; ahead of AutoHotkey's hook and replaces a hook Windows has removed, and
; shortly after each change of the active window, which keeps it ahead of
; clients that install their own hook when they get focus.
;
; It also tracks the Windows keys. A remote session client's hook may take
; Win for the remote machine before AutoHotkey's hook sees it; this hook,
; ahead of the client's, still does (see Bindings.WinSwallowed).
class SimulatedKeys {
    static enabled := false
    static MaxAgeMs := 1000
    static ReinstallMs := 30000
    static ForegroundReinstallDelays := [50, 300]
    ; A held Win key that sent no key-down (press or auto-repeat) for this long
    ; counts as released, in case its release was missed.
    static WinMaxQuietMs := 10000
    static _hook := 0
    static _callback := 0
    static _timer := ""
    static _winEventHook := 0
    static _winEventCallback := 0
    ; The latest keyboard event: virtual key, injected flag, key up, event time
    ; (GetTickCount milliseconds).
    static last := { vk: 0, injected: false, up: false, time: 0 }
    ; Virtual keys typed (not injected) and not yet released, as this hook saw
    ; them. Owners may Clear() it: RemoteSessions does on each activation.
    static down := Map()
    ; Optional fn(vk, up) called for every typed (not injected) key event,
    ; inside the hook: it must return quickly and leave sending to a timer.
    static OnTyped := ""
    ; A_TickCount when the last typed key in `down` was released.
    static emptyAt := 0
    ; Typed Win keys as this hook saw them: A_TickCount of the latest key-down
    ; while held, 0 when up.
    static winDown := { L: 0, R: 0 }
    ; Optional fn(vk, sc, up, injected) called for every key event, inside the
    ; hook, after `last` is updated (sc is the scan code, plus 0x100 for an
    ; extended key); returning true blocks the event from every later hook
    ; and from the system. It must return quickly.
    static Intercept := ""

    ; mutate: off (Windows hook plumbing)
    static Enable() {
        if (SimulatedKeys.enabled)
            return
        SimulatedKeys._callback := CallbackCreate((nCode, wParam, lParam) => SimulatedKeys._Proc(nCode, wParam, lParam), "Fast", 3)
        try {
            SimulatedKeys._Install()
        } catch as e {
            CallbackFree(SimulatedKeys._callback)
            SimulatedKeys._callback := 0
            throw e
        }
        SimulatedKeys.enabled := true
        SimulatedKeys._timer := () => SimulatedKeys._Reinstall()
        SetTimer(SimulatedKeys._timer, SimulatedKeys.ReinstallMs)
        ; EVENT_SYSTEM_FOREGROUND, out of context: delivered through this thread's message loop.
        SimulatedKeys._winEventCallback := CallbackCreate((args*) => SimulatedKeys._OnForeground(), "F", 7)
        SimulatedKeys._winEventHook := DllCall("SetWinEventHook", "uint", 3, "uint", 3, "ptr", 0,
            "ptr", SimulatedKeys._winEventCallback, "uint", 0, "uint", 0, "uint", 0, "ptr")
    }

    static _OnForeground() {
        ; One closure per delay: SetTimer on the same function would just move one timer.
        for delay in SimulatedKeys.ForegroundReinstallDelays
            SetTimer(((d, *) => SimulatedKeys._Reinstall()).Bind(delay), -delay)
    }

    static Disable() {
        if !SimulatedKeys.enabled
            return
        SimulatedKeys.enabled := false
        SetTimer(SimulatedKeys._timer, 0)
        if (SimulatedKeys._winEventHook)
            DllCall("UnhookWinEvent", "ptr", SimulatedKeys._winEventHook)
        SimulatedKeys._winEventHook := 0
        if (SimulatedKeys._winEventCallback)
            CallbackFree(SimulatedKeys._winEventCallback)
        SimulatedKeys._winEventCallback := 0
        SimulatedKeys.winDown := { L: 0, R: 0 }
        if (SimulatedKeys._hook)
            DllCall("UnhookWindowsHookEx", "ptr", SimulatedKeys._hook)
        SimulatedKeys._hook := 0
        CallbackFree(SimulatedKeys._callback)
        SimulatedKeys._callback := 0
    }

    ; Installs a new hook before removing the old one, so no event is missed.
    static _Install() {
        hook := DllCall("SetWindowsHookExW", "int", 13, "ptr", SimulatedKeys._callback,
            "ptr", DllCall("GetModuleHandleW", "ptr", 0, "ptr"), "uint", 0, "ptr")
        if !hook
            throw OSError(A_LastError, , "SetWindowsHookEx")
        old := SimulatedKeys._hook
        SimulatedKeys._hook := hook
        if (old)
            DllCall("UnhookWindowsHookEx", "ptr", old)
    }

    static _Reinstall() {
        if SimulatedKeys.enabled
            try SimulatedKeys._Install()
    }

    static _Proc(nCode, wParam, lParam) {
        if (nCode >= 0) {
            flags := NumGet(lParam, 8, "uint")
            SimulatedKeys.last := {
                vk: NumGet(lParam, 0, "uint"),
                injected: (flags & 0x10) != 0,
                up: (flags & 0x80) != 0,
                time: NumGet(lParam, 12, "uint"),
            }
            ; Typed keys only: an injected release (RemoteSessions.ReleaseKey) leaves
            ; the physical key held. Never throw here: this runs inside the hook.
            if (!SimulatedKeys.last.injected) {
                if (!SimulatedKeys.last.up)
                    SimulatedKeys.down[SimulatedKeys.last.vk] := true
                else if SimulatedKeys.down.Has(SimulatedKeys.last.vk) {
                    SimulatedKeys.down.Delete(SimulatedKeys.last.vk)
                    if !SimulatedKeys.down.Count
                        SimulatedKeys.emptyAt := A_TickCount
                }
                if (SimulatedKeys.last.vk = 0x5B || SimulatedKeys.last.vk = 0x5C)
                    SimulatedKeys.winDown.%(SimulatedKeys.last.vk = 0x5B ? "L" : "R")% := SimulatedKeys.last.up ? 0 : A_TickCount
                if (SimulatedKeys.OnTyped != "")
                    try SimulatedKeys.OnTyped.Call(SimulatedKeys.last.vk, SimulatedKeys.last.up)
            }
            if (SimulatedKeys.Intercept != "") {
                block := false
                sc := (NumGet(lParam, 4, "uint") & 0xFF) | ((flags & 0x1) ? 0x100 : 0)
                try block := SimulatedKeys.Intercept.Call(SimulatedKeys.last.vk, sc, SimulatedKeys.last.up, SimulatedKeys.last.injected)
                if block
                    return 1
            }
        }
        return DllCall("CallNextHookEx", "ptr", 0, "int", nCode, "ptr", wParam, "ptr", lParam, "ptr")
    }
    ; mutate: on

    ; Whether this hook saw a Win key go down and not up: side "L", "R", or ""
    ; for either. False while the hook isn't running.
    static WinHeld(side := "") {
        if !SimulatedKeys.enabled
            return false
        w := SimulatedKeys.winDown, now := A_TickCount, quiet := SimulatedKeys.WinMaxQuietMs
        if (side = "L" || side = "R")
            return SimulatedKeys.IsHeld(w.%side%, now, quiet)
        return SimulatedKeys.IsHeld(w.L, now, quiet) || SimulatedKeys.IsHeld(w.R, now, quiet)
    }

    ; Pure: whether a key last seen going down at `downAt` (0 = up) still
    ; counts as held at `now`.
    static IsHeld(downAt, now, maxQuietMs) => downAt != 0 && now - downAt <= maxQuietMs

    ; Whether a hotkey may fire on the event being processed. `hotkeyName` is
    ; the hotkey AutoHotkey passes to #HotIf callbacks.
    static Allows(hotkeyName) {
        if !SimulatedKeys.enabled
            return true
        last := SimulatedKeys.last
        vk := 0
        try vk := GetKeyVK(HotkeyText.BaseKey(hotkeyName))
        return SimulatedKeys.Decide(last.injected, last.vk, vk, (A_TickCount - last.time) & 0xFFFFFFFF, SimulatedKeys.MaxAgeMs)
    }

    ; Pure: blocks only when the recorded event is simulated, is for the
    ; hotkey's key, and is fresh; anything uncertain is allowed.
    static Decide(injected, recordedVk, hotkeyVk, ageMs, maxAgeMs) {
        if !injected
            return true
        if (!hotkeyVk || !SimulatedKeys.SameKey(recordedVk, hotkeyVk))
            return true
        return ageMs > maxAgeMs
    }

    ; Pure: the hook reports sided modifier codes (LCtrl 0xA2); a hotkey on a
    ; generic modifier (Ctrl 0x11) matches either side.
    static SameKey(recordedVk, hotkeyVk) {
        if (recordedVk = hotkeyVk)
            return true
        static generic := Map(0xA0, 0x10, 0xA1, 0x10, 0xA2, 0x11, 0xA3, 0x11, 0xA4, 0x12, 0xA5, 0x12)
        return generic.Has(recordedVk) && generic[recordedVk] = hotkeyVk
    }
}
