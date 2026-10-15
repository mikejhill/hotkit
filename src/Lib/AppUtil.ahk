#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\WindowUtil.ahk
#Include %A_LineFile%\..\Toast.ahk
#Include %A_LineFile%\..\HotkeyText.ahk

class AppUtil {
    ; Opens the given application, acquiring or minimizing the window if it is already open.
    ; With cycle, switches between the application's windows instead (see CycleApp).
    static OpenApp(appName, appPath, winPattern, launchOptions?, cycle := false) {
        hwnd := cycle ? AppUtil.CycleApp(winPattern) : AppUtil.ToggleApp(winPattern)
        if (!hwnd) {
            AppUtil.LaunchApp(appName, appPath, launchOptions?)
        }
    }

    ; Toggles the given application window (minimizes if active, activates if inactive).
    static ToggleApp(winPattern) {
        origTitleMatchMode := A_TitleMatchMode
        SetTitleMatchMode("RegEx")
        ; TODO: If multiple windows match, then a different window opens each time; fix
        hwnd := WinExist(winPattern)
        SetTitleMatchMode(origTitleMatchMode)
        if (hwnd) {
            if (WinActive(hwnd) = hwnd) {
                nextHwnd := WindowUtil.GetNextActivatableWindow(hwnd)
                WinMinimize(hwnd)
                if (nextHwnd && WinExist("ahk_id " nextHwnd)) {
                    WinActivate(nextHwnd)
                }
            } else {
                WinActivate(hwnd)
                WinMoveTop(hwnd)
            }
        }
        return hwnd
    }

    ; Activates the next window of the given application, wrapping around. Never minimizes.
    ; Skips hidden helper windows and windows cloaked on other virtual desktops; keeps
    ; minimized ones. Returns the activated window, or 0 when the app has no windows.
    static CycleApp(winPattern) {
        origTitleMatchMode := A_TitleMatchMode
        SetTitleMatchMode("RegEx")
        list := WinGetList(winPattern)  ; z-order, front to back
        SetTitleMatchMode(origTitleMatchMode)
        windows := []
        for h in list {
            try {
                if (!DllCall("user32\IsWindowVisible", "ptr", h, "int") || WindowUtil.IsCloaked(h))
                    continue
            } catch {
                continue
            }
            windows.Push(h)
        }
        hwnd := AppUtil.CycleTarget(windows, WinExist("A"))
        if (hwnd) {
            WinActivate(hwnd)
            WinMoveTop(hwnd)
        }
        return hwnd
    }

    ; Pure: which window to activate next. `windows` is in z-order (front to back).
    ; If none of the app's windows is active, the most recently used one; otherwise the
    ; bottom-most, so repeated presses rotate through every window.
    static CycleTarget(windows, activeHwnd) {
        if (!windows.Length)
            return 0
        for h in windows {
            if (h = activeHwnd)
                return windows[windows.Length]
        }
        return windows[1]
    }

    ; Opens the given application, displaying a tooltip on success or failure.
    static LaunchApp(appName, appPath, launchOptions?) {
        try {
            Run(appPath, , launchOptions?)
            Toast.ShowToast(, "Executing:", appName)
        } catch as e {
            Toast.ShowToast({ color: "Red", fadeDelay: 5000 }, "Failed to launch:`n" . appName, "Error:`n" . e.Message)
        }
    }

    ; Compatibility forwarding for existing scripts. New callers use WindowUtil.
    static ToggleActiveWindowMinimized() => WindowUtil.ToggleActiveWindowMinimized()
    static FocusNextWindow() => WindowUtil.FocusNextWindow()
    static GetNextActivatableWindow(cur) => WindowUtil.GetNextActivatableWindow(cur)
    static IsAltTabCandidate(hwnd) => WindowUtil.IsAltTabCandidate(hwnd)
    ; Converts hotkey notation into a SendEvent sequence (see HotkeyText.ToSendEvent).
    static HotkeyToSendEvent(hk) => HotkeyText.ToSendEvent(hk)

    ; Triggers the hotkey matching the given binding.
    static RunHotkey(binding) {
        sendEventStr := AppUtil.HotkeyToSendEvent(binding)
        previousLevel := A_SendLevel
        SendLevel(1)
        SendEvent(sendEventStr)
        SendLevel(previousLevel)
    }

    ; Helper to bind methods with parameters, such as for use in Menu callbacks. This differs from Func.Bind
    ; by returning a lambda that calls the method with the given parameters only, rather than passing along any extra parameters from the caller.
    static BindMethod(method, params*) {
        return (*) => method(params*)
    }
}
