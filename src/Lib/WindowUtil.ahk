#Requires AutoHotkey v2.0

; Shared window operations. Targets accept an HWND or normal AHK WinTitle.
; Missing targets throw TargetError; no hotkeys, toasts, or app-launch behavior.
class WindowUtil {
    static _Indicators := Map()
    static _CleanupCallback := (*) => WindowUtil.CleanAlwaysOnTopIndicators()
    static _ExitCallback := (*) => WindowUtil.RestoreAlwaysOnTopIndicators()
    static _ExitRegistered := false

    static GetHandle(winTitle := "A") {
        hwnd := WinExist(winTitle)
        if (!hwnd)
            throw TargetError("Window not found.", , winTitle)
        return hwnd
    }

    static GetAlwaysOnTop(winTitle := "A") {
        return !!(WinGetExStyle(WindowUtil.GetHandle(winTitle)) & 0x8)
    }

    ; Set accepts true/false; Toggle returns the resulting topmost state.
    static SetAlwaysOnTop(enabled, winTitle := "A") {
        hwnd := WindowUtil.GetHandle(winTitle)
        WinSetAlwaysOnTop(!!enabled, hwnd)
        return WindowUtil.GetAlwaysOnTop(hwnd)
    }

    static ToggleAlwaysOnTop(winTitle := "A") {
        hwnd := WindowUtil.GetHandle(winTitle)
        return WindowUtil.SetAlwaysOnTop(!WindowUtil.GetAlwaysOnTop(hwnd), hwnd)
    }

    ; Windows 11 native border, with system-controlled thickness. Color is an
    ; RGB integer (0x4F8CC9) or exactly six hex digits ("4F8CC9" / "#4F8CC9").
    ; Example: WindowUtil.SetBorderColor("#4F8CC9", hwnd)
    ; Custom/fullscreen frames may hide it. No overlays or geometry polling.
    static SetBorderColor(color, winTitle := "A") {
        if (Type(color) = "String") {
            if (!RegExMatch(color, "^#?([0-9A-Fa-f]{6})$", &match))
                throw ValueError("Border color must contain six hexadecimal digits.")
            color := Integer("0x" match[1])
        }
        if (!IsInteger(color) || color < 0 || color > 0xFFFFFF)
            throw ValueError("Border color must be an RGB integer from 0x000000 to 0xFFFFFF.")
        bgr := ((color & 0xFF) << 16) | (color & 0xFF00) | ((color >> 16) & 0xFF)
        WindowUtil._SetNativeBorderColor(WindowUtil.GetHandle(winTitle), bgr)
    }

    ; The native border attribute is write-only; reset restores system defaults,
    ; not an application's previous custom color.
    static ResetBorderColor(winTitle := "A") {
        WindowUtil._SetNativeBorderColor(WindowUtil.GetHandle(winTitle), 0xFFFFFFFF)
    }

    static HideBorder(winTitle := "A") {
        WindowUtil._SetNativeBorderColor(WindowUtil.GetHandle(winTitle), 0xFFFFFFFE)
    }

    static IsCloaked(winTitle := "A") {
        hwnd := WindowUtil.GetHandle(winTitle)
        cloaked := 0
        result := DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 14,
            "uint*", &cloaked, "uint", 4, "int")
        if (result < 0)
            throw Error("Cannot read window cloaking state.")
        return !!cloaked
    }

    ; Optional managed indicator. The caller pins the window first.
    ; Cleanup resets the border after external unpinning or script exit.
    static AddAlwaysOnTopIndicator(hwnd, color := "4F8CC9") {
        hwnd := WindowUtil.GetHandle(hwnd)

        if (WindowUtil._Indicators.Has(hwnd))
            return
        entry := { pid: WinGetPID(hwnd) }
        WindowUtil.SetBorderColor(color, hwnd)
        if (!WindowUtil._ExitRegistered) {
            OnExit(WindowUtil._ExitCallback)
            WindowUtil._ExitRegistered := true
        }
        WindowUtil._Indicators[hwnd] := entry
        ; Only check lifetime/topmost state once per second, never window position.
        SetTimer(WindowUtil._CleanupCallback, 1000)
    }

    static _SetNativeBorderColor(hwnd, color) {
        result := DllCall("Dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "uint", 34,
            "uint*", &color, "uint", 4, "int")
        if (result < 0)
            throw Error("Cannot set native border color (HRESULT " Format("0x{:08X}", result & 0xFFFFFFFF) ").")
    }

    static RemoveAlwaysOnTopIndicator(hwnd) {

        if (!WindowUtil._Indicators.Has(hwnd))
            return
        entry := WindowUtil._Indicators[hwnd]
        if (DllCall("User32\IsWindow", "ptr", hwnd) && WinGetPID(hwnd) = entry.pid) {
            ; DWMWA_BORDER_COLOR is write-only; restore Windows default behavior.
            WindowUtil.ResetBorderColor(hwnd)
        }
        WindowUtil._Indicators.Delete(hwnd)
        if (!WindowUtil._Indicators.Count)
            SetTimer(WindowUtil._CleanupCallback, 0)
    }

    static CleanAlwaysOnTopIndicators(*) {

        stale := []
        for hwnd, entry in WindowUtil._Indicators {
            try {
                if (WinGetPID(hwnd) = entry.pid && (WinGetExStyle(hwnd) & 0x8))
                    continue
            }
            stale.Push(hwnd)
        }
        for hwnd in stale {
            try WindowUtil.RemoveAlwaysOnTopIndicator(hwnd)
        }
    }

    static RestoreAlwaysOnTopIndicators(*) {

        SetTimer(WindowUtil._CleanupCallback, 0)
        handles := []
        for hwnd in WindowUtil._Indicators
            handles.Push(hwnd)
        for hwnd in handles {
            try WindowUtil.RemoveAlwaysOnTopIndicator(hwnd)
        }
        ; Leave the windows' topmost state unchanged on exit/reload.
    }

    ; ---------------- Window Focus Management        ------------------------------

    ; Minimize the active window, or restore the window most recently minimized by this method when no real window is active.
    static ToggleActiveWindowMinimized() {
        static lastMinimizedHwnd := 0

        hwnd := WinExist("A")
        if (hwnd && WindowUtil.IsAltTabCandidate(hwnd)) {
            lastMinimizedHwnd := hwnd
            WinMinimize("ahk_id " hwnd)
            return
        }

        if (lastMinimizedHwnd && WinExist("ahk_id " lastMinimizedHwnd) && WinGetMinMax("ahk_id " lastMinimizedHwnd) = -1) {
            WinRestore("ahk_id " lastMinimizedHwnd)
            WinActivate("ahk_id " lastMinimizedHwnd)
            lastMinimizedHwnd := 0
        }
    }

    ; Focus the next activatable window in z-order, or wrap to the first window.
    ; Skips windows that are not eligible for Alt+Tab (cloaked, minimized, toolwindows, etc).
    static FocusNextWindow() {
        cur := WinExist("A")
        if (!cur) {
            return
        }

        nextHwnd := WindowUtil.GetNextActivatableWindow(cur)
        if (nextHwnd) {
            WinActivate(nextHwnd)
        }
    }

    ; Find the next activatable window in z-order without changing focus.
    ; Windows listed in `exclude` (an Array of hwnds) are skipped.
    static GetNextActivatableWindow(cur, exclude := "") {
        skip := Map()
        if (exclude is Array) {
            for h in exclude
                skip[h] := true
        }
        list := WinGetList() ; top-level windows in z-order (front to back)
        for (i, h in list) {
            if (h = cur) {
                ; Pick the next *activatable* window after current, wrapping around
                loop (list.Length - 1) {
                    cand := list[Mod(i - 1 + A_Index, list.Length) + 1]
                    if (!skip.Has(cand) && WindowUtil.IsAltTabCandidate(cand)) {
                        return cand
                    }
                }
                return 0
            }
        }
        return 0
    }

    ; ---------------- Z-order (stacking) ------------------------------------------

    ; Move a window within the stacking order without activating, minimizing, or
    ; hiding it, so it keeps focus. direction is "backward" (behind the next
    ; overlapping window), "back" (behind all), "forward" (in front of the next
    ; overlapping window above), or "front" (in front of all). Always-on-top
    ; windows move only among always-on-top windows, and others never pass them.
    ; An owned window (dialog) moves with its owner. Returns false when nothing
    ; needs to move; throws OSError when Windows refuses the move.
    ; mutate: off
    static MoveInZOrder(direction, winTitle := "A") {
        active := hwnd := WindowUtil.GetHandle(winTitle)
        ; Owned windows must stay above their owner. Windows moves an owner with
        ; its owned windows, Wine does not, so the root owner, the top visible
        ; owner and the window itself are each placed, in that order. The stack
        ; position is read from the top visible owner, because a hidden owner
        ; (common for app and AHK GUI windows) is not in the visible stack.
        root := DllCall("user32\GetAncestor", "ptr", hwnd, "uint", 3, "ptr") || hwnd ; GA_ROOTOWNER
        while ((owner := DllCall("user32\GetWindow", "ptr", hwnd, "uint", 4, "ptr")) && DllCall("user32\IsWindowVisible", "ptr", owner, "int")) ; GW_OWNER
            hwnd := owner
        entries := []
        index := 0
        for h in WinGetList() {
            if (h = hwnd)
                index := entries.Length + 1
            else if (!WindowUtil.IsZOrderPeer(h)) {
                entries.Push({ hwnd: h, topmost: !!(WinGetExStyle(h) & 0x8), peer: false })
                continue
            }
            WinGetPos(&x, &y, &w, &hgt, h)
            entries.Push({ hwnd: h, topmost: !!(WinGetExStyle(h) & 0x8), peer: true,
                rect: { left: x, top: y, right: x + w, bottom: y + hgt } })
        }
        if (!index)
            return false
        insertAfter := WindowUtil.ZOrderInsertAfter(entries, index, direction)
        if (insertAfter = "")
            return false
        ; Only windows in the target's band move, so an always-on-top dialog of
        ; a normal window (or the reverse) keeps its topmost state.
        band := entries[index].topmost
        moved := Map()
        for h in [root, hwnd, active] {
            if (moved.Has(h) || !!(WinGetExStyle(h) & 0x8) != band)
                continue
            moved[h] := true
            ; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
            if (!DllCall("user32\SetWindowPos", "ptr", h, "ptr", insertAfter,
                "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x13, "int"))
                throw OSError(A_LastError, , "SetWindowPos")
        }
        return true
    }
    ; mutate: on

    ; Pure: where to put entries[index] for a move. entries are front to back,
    ; each { hwnd, topmost, peer, rect: { left, top, right, bottom } } (rect only
    ; needed on peers). Returns the hwnd to insert after, 0 for the top of the
    ; window's band (HWND_TOP), or "" when the window is already in place.
    static ZOrderInsertAfter(entries, index, direction) {
        self := entries[index]
        isPeer(e) => e.peer && e.topmost = self.topmost
        overlaps(e) => e.rect.left < self.rect.right && self.rect.left < e.rect.right
            && e.rect.top < self.rect.bottom && self.rect.top < e.rect.bottom
        switch direction, false {
            case "backward":
                loop entries.Length - index {
                    e := entries[index + A_Index]
                    if (isPeer(e) && overlaps(e))
                        return e.hwnd
                }
                return ""
            case "back":
                loop entries.Length - index {
                    e := entries[entries.Length - A_Index + 1]
                    if (isPeer(e))
                        return e.hwnd
                }
                return ""
            case "forward":
                loop index - 1 {
                    j := index - A_Index
                    if (!isPeer(entries[j]) || !overlaps(entries[j]))
                        continue
                    above := j > 1 ? entries[j - 1] : ""
                    return (above && above.topmost = self.topmost) ? above.hwnd : 0
                }
                return ""
            case "front":
                loop index - 1 {
                    if (isPeer(entries[A_Index]))
                        return 0
                }
                return ""
        }
        throw ValueError("Unknown z-order direction: " direction)
    }

    ; A window worth stepping past: one Alt+Tab would list (visible, restored,
    ; not cloaked, not a tool window, and unowned or WS_EX_APPWINDOW), that is
    ; not the desktop, the taskbar, or a click-through overlay.
    static IsZOrderPeer(hwnd) {
        try {
            if (!DllCall("user32\IsWindowVisible", "ptr", hwnd, "int") || DllCall("user32\IsIconic", "ptr", hwnd, "int"))
                return false
            ex := WinGetExStyle(hwnd)
            if ((ex & 0x80) || (ex & 0x80020) = 0x80020) ; WS_EX_TOOLWINDOW; WS_EX_LAYERED | WS_EX_TRANSPARENT
                return false
            if (!(ex & 0x40000) && DllCall("user32\GetWindow", "ptr", hwnd, "uint", 4, "ptr")) ; WS_EX_APPWINDOW; GW_OWNER
                return false
            try {
                if (WindowUtil.IsCloaked(hwnd))
                    return false
            }
            cls := WinGetClass(hwnd)
            return !(cls = "Progman" || cls = "WorkerW" || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd")
        }
        return false
    }

    ; Determine if a window is a valid Alt+Tab candidate.
    ; Returns true if window is visible, not minimized, not cloaked, and not a toolwindow.
    static IsAltTabCandidate(hwnd) {
        if (!DllCall("user32\IsWindowVisible", "ptr", hwnd, "int")) {
            return false
        }

        ; Skip toolwindows (these usually don't appear in Alt+Tab)
        exStyle := WinGetExStyle(hwnd) ; GWL_EXSTYLE=-20
        if ((exStyle & 0x80) != 0) { ; WS_EX_TOOLWINDOW=0x80
            return false
        }

        ; Skip owned popups (often excluded from Alt+Tab)
        owner := DllCall("user32\GetWindow", "ptr", hwnd, "uint", 4, "ptr") ; GW_OWNER=4
        if (owner != 0) {
            return false
        }

        ; Skip cloaked windows (Win10/11 virtual desktop/UWP cloaking). Without DWM
        ; (e.g. under Wine) the state can't be read; treat the window as visible.
        try {
            if (WindowUtil.IsCloaked(hwnd)) {
                return false
            }
        }

        ; Skip minimized windows
        if (DllCall("user32\IsIconic", "ptr", hwnd, "int")) {
            return false
        }

        return true
    }
}
