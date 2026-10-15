#Requires AutoHotkey v2.0

; Remembers the order in which top-level windows were focused, using the shell
; hook (HSHELL_WINDOWACTIVATED / HSHELL_RUDEAPPACTIVATED). Z-order alone cannot
; answer "which window did I use last": minimizing a window sends it to the
; bottom, so a later toggle would raise a different one.
class FocusHistory {
    static Seq := Map()      ; hwnd -> focus sequence number (higher = more recent)
    static Counter := 0
    static Started := false
    static MaxEntries := 500
    static _ignoreUntil := 0

    ; mutate: off (shell hook registration; covered by e2e)
    static Start() {
        if FocusHistory.Started
            return
        DllCall("RegisterShellHookWindow", "ptr", A_ScriptHwnd)
        msg := DllCall("RegisterWindowMessage", "str", "SHELLHOOK", "uint")
        OnMessage(msg, (wParam, lParam, *) => FocusHistory._OnShell(wParam, lParam))
        FocusHistory.Started := true
        try FocusHistory.Note(WinExist("A"))
    }

    static _OnShell(wParam, lParam) {
        if (A_TickCount < FocusHistory._ignoreUntil)
            return
        if (wParam = 4 || wParam = 0x8004)  ; HSHELL_WINDOWACTIVATED, HSHELL_RUDEAPPACTIVATED
            FocusHistory.Note(lParam)
    }

    ; Ignores activations for `ms`: when a window is minimized, Windows briefly
    ; activates whatever is next in z-order, which is not a choice the user made.
    static Pause(ms := 750) {
        FocusHistory._ignoreUntil := A_TickCount + ms
    }

    ; mutate: on
    ; Records `hwnd` as the most recently focused window.
    static Note(hwnd) {
        if !hwnd
            return
        FocusHistory.Seq[hwnd] := ++FocusHistory.Counter
        if (FocusHistory.Seq.Count > FocusHistory.MaxEntries)
            FocusHistory._Prune()
    }

    ; mutate: off (reads live window state)
    static _Prune() {
        stale := []
        for hwnd in FocusHistory.Seq {
            if !WinExist("ahk_id " hwnd)
                stale.Push(hwnd)
        }
        for hwnd in stale
            FocusHistory.Seq.Delete(hwnd)
    }

    ; mutate: on
    ; Pure: the window in `windows` (z-order, front to back) that was focused most
    ; recently according to `seq` (hwnd -> sequence). Windows never seen focused
    ; rank below any seen one; ties keep z-order. Returns 0 for an empty list.
    static MostRecent(windows, seq) {
        best := 0, bestSeq := -1
        for hwnd in windows {
            s := seq.Has(hwnd) ? seq[hwnd] : 0
            if (s > bestSeq) {
                best := hwnd
                bestSeq := s
            }
        }
        return best
    }
}
