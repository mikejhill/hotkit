#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\WindowUtil.ahk
#Include %A_LineFile%\..\Debugger.ahk
#Include %A_LineFile%\..\Toast.ahk

; A summonable "quick window": toggle any app window in and out of view with
; one key, optionally as a floating always-on-top tool window, with support for
; several windows of the same app and multiple launch modes.
;
; The caller supplies what to launch and how to recognize the app's windows:
;   qw := QuickWindow("Notes", "notepad.exe",
;       (manager, existing) => Run("notepad.exe"),
;       (hwnd) => WinGetClass(hwnd) = "Notepad",
;       Map("alwaysOnTop", true, "toolWindow", true))
;   qw.Toggle()
;
; Options (Map): modes, toolWindow, alwaysOnTop, claimExisting, multipleWindows,
;   launchTimeoutSeconds, widthRatio, heightRatio.
; Window state is stored in a window property so styles can be restored after a
; crash or reload (see Recover()).
class QuickWindow {
    static ToolWindow := 0x80
    static AppWindow := 0x40000
    static Topmost := 0x8
    static ClickThrough := 0x20

    __New(name, exeName, launchWindow, isTarget, options?) {
        options := IsSet(options) ? options : Map()
        this.name := name
        this.exeName := exeName
        this.launchWindow := launchWindow
        this.isTarget := isTarget
        this.modes := options.Get("modes", [])
        this.toolWindow := options.Get("toolWindow", false)
        this.alwaysOnTop := options.Get("alwaysOnTop", false)
        this.claimExisting := options.Get("claimExisting", false)
        this.multipleWindows := options.Get("multipleWindows", false)
        this.launchTimeoutSeconds := options.Get("launchTimeoutSeconds", 10)
        this.widthRatio := options.Get("widthRatio", 0.5)
        this.heightRatio := options.Get("heightRatio", 0.5)
        this.modeIndex := 1
        this.windows := []
        this.currentIndex := 0
        this.creating := false
        this.propertyName := "AHK.QuickWindow." name
        this.Recover()
        OnExit((*) => this.Recover())
    }

    Toggle() {
        this.Clean()
        if (this.claimExisting)
            this.AdoptExisting()
        if (!this.windows.Length) {
            this.Create()
            return
        }
        hwnd := this.windows[this.currentIndex]
        if (this.IsActive(hwnd)) {
            this.Hide(hwnd)
            WindowUtil.FocusNextWindow()
        } else {
            this.Activate(this.currentIndex)
        }
    }

    Create() {
        if (this.creating)
            return
        this.creating := true
        newHwnd := 0
        try {
            this.Clean()
            before := this.GetCandidates()
            if (!this.multipleWindows && before.Length) {
                Toast.ShowToast(, this.name " new window unavailable", "The installed app has no CLI parameter for a second window.")
                return
            }
            this.SetManagedTopmost(false)
            this.launchWindow.Call(this, before)
            newHwnd := this.WaitForNewWindow(before)
            if (!newHwnd)
                throw Error("No new " this.name " window appeared within " this.launchTimeoutSeconds " seconds.")
            this.Track(newHwnd)
            this.PositionInitially(newHwnd)
            this.Activate(this.currentIndex)
        } catch as caughtError {
            if (newHwnd && DllCall("GetPropW", "ptr", newHwnd, "str", this.propertyName, "ptr")) {
                try this.Restore(newHwnd)
                for index, trackedHwnd in this.windows {
                    if (trackedHwnd = newHwnd) {
                        this.windows.RemoveAt(index)
                        break
                    }
                }
                this.Clean()
            }
            Debugger.Log(this.name ": " caughtError.Message)
            Toast.ShowToast({color: "Red", fadeDelay: 5000}, this.name " window failed", caughtError.Message)
        } finally {
            this.SetManagedTopmost(true)
            this.creating := false
        }
    }

    Cycle() {
        this.Clean()
        if (this.claimExisting)
            this.AdoptExisting(true)
        if (!this.windows.Length)
            return
        hwnd := this.windows[this.currentIndex]
        if (!this.IsActive(hwnd) || this.windows.Length = 1) {
            this.Activate(this.currentIndex)
            return
        }
        this.Activate(Mod(this.currentIndex, this.windows.Length) + 1)
    }

    ShowAll() {
        this.Clean()
        if (this.claimExisting)
            this.AdoptExisting(true)
        for hwnd in this.windows
            this.Reveal(hwnd)
    }

    Detach() {
        this.Clean()
        for hwnd in this.windows
            this.Restore(hwnd)
        this.windows := []
        this.currentIndex := 0
    }

    CycleMode() {
        if (!this.modes.Length)
            return
        this.modeIndex := Mod(this.modeIndex, this.modes.Length) + 1
        Toast.ShowToast(, "Selected mode [" this.modeIndex "]: [" this.CurrentMode() "]")
    }

    CurrentMode() => this.modes.Length ? this.modes[this.modeIndex] : ""

    AdoptExisting(includeOtherWindows := false) {
        candidates := this.GetCandidates()
        activeHwnd := WinActive("ahk_exe " this.exeName)
        previousIndex := this.currentIndex
        activeIndex := 0
        for hwnd in candidates {
            if (hwnd = activeHwnd) {
                activeIndex := this.Claim(hwnd)
                break
            }
        }
        if (includeOtherWindows) {
            for hwnd in candidates
                this.Claim(hwnd)
        } else if (!this.windows.Length && candidates.Length) {
            this.Claim(candidates[1])
        }
        if (this.windows.Length)
            this.currentIndex := activeIndex ? activeIndex : (previousIndex ? previousIndex : 1)
        return this.windows.Length > 0
    }

    Claim(hwnd) {
        for index, trackedHwnd in this.windows {
            if (trackedHwnd = hwnd)
                return index
        }
        if (DllCall("GetPropW", "ptr", hwnd, "str", this.propertyName, "ptr")) {
            ; A prior instance may have marked the window without retaining it in memory.
            this.ApplyManagedStyle(hwnd)
            this.windows.Push(hwnd)
            this.currentIndex := this.windows.Length
        } else {
            if (this.claimExisting && this.IsOrphan(hwnd))
                this.RepairOrphan(hwnd)
            this.Track(hwnd)
        }
        return this.currentIndex
    }

    IsOrphan(hwnd) {
        style := WinGetExStyle("ahk_id " hwnd)
        alpha := WinGetTransparent("ahk_id " hwnd)
        return (style & (QuickWindow.ToolWindow | QuickWindow.ClickThrough))
            || (alpha != "" && alpha = 0)
    }

    RepairOrphan(hwnd) {
        this.Reveal(hwnd)
        WinSetExStyle("-" QuickWindow.ToolWindow, "ahk_id " hwnd)
        if (this.toolWindow)
            WinSetExStyle("+" QuickWindow.AppWindow, "ahk_id " hwnd)
        WinSetAlwaysOnTop(false, "ahk_id " hwnd)
    }

    GetCandidates() {
        result := []
        previous := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            for hwnd in WinGetList("ahk_exe " this.exeName) {
                try {
                    if (DllCall("GetPropW", "ptr", hwnd, "str", this.propertyName, "ptr") || this.isTarget.Call(hwnd))
                        result.Push(hwnd)
                }
            }
        } finally {
            DetectHiddenWindows(previous)
        }
        return result
    }

    WaitForNewWindow(before) {
        loop Ceil(this.launchTimeoutSeconds * 1000 / 250) {
            Sleep(250)
            for hwnd in this.GetCandidates() {
                found := false
                for previousHwnd in before {
                    if (hwnd = previousHwnd) {
                        found := true
                        break
                    }
                }
                if (!found)
                    return hwnd
            }
        }
        return 0
    }

    Track(hwnd) {
        style := WinGetExStyle("ahk_id " hwnd)
        alpha := WinGetTransparent("ahk_id " hwnd)
        saved := 0x100000 | (style & (QuickWindow.ToolWindow | QuickWindow.AppWindow | QuickWindow.Topmost | QuickWindow.ClickThrough))
        if (alpha != "")
            saved |= 0x10000 | (alpha << 8)
        if (!DllCall("SetPropW", "ptr", hwnd, "str", this.propertyName, "ptr", saved, "int"))
            throw Error("Could not mark the new window for recovery.")
        this.ApplyManagedStyle(hwnd)
        this.windows.Push(hwnd)
        this.currentIndex := this.windows.Length
    }

    ApplyManagedStyle(hwnd) {
        if (this.toolWindow) {
            WinSetExStyle("-" QuickWindow.AppWindow, "ahk_id " hwnd)
            WinSetExStyle("+" QuickWindow.ToolWindow, "ahk_id " hwnd)
        }
        if (this.alwaysOnTop)
            WinSetAlwaysOnTop(true, "ahk_id " hwnd)
    }

    Restore(hwnd) {
        saved := DllCall("GetPropW", "ptr", hwnd, "str", this.propertyName, "ptr")
        if (!saved)
            return
        try {
            this.Reveal(hwnd)
            WinSetExStyle((saved & QuickWindow.ToolWindow) ? ("+" QuickWindow.ToolWindow) : ("-" QuickWindow.ToolWindow), "ahk_id " hwnd)
            WinSetExStyle((saved & QuickWindow.AppWindow) ? ("+" QuickWindow.AppWindow) : ("-" QuickWindow.AppWindow), "ahk_id " hwnd)
            WinSetExStyle((saved & QuickWindow.ClickThrough) ? ("+" QuickWindow.ClickThrough) : ("-" QuickWindow.ClickThrough), "ahk_id " hwnd)
            if (saved & 0x10000)
                WinSetTransparent((saved >> 8) & 0xff, "ahk_id " hwnd)
            else
                WinSetTransparent("Off", "ahk_id " hwnd)
            WinSetAlwaysOnTop(!!(saved & QuickWindow.Topmost), "ahk_id " hwnd)
        } finally {
            DllCall("RemovePropW", "ptr", hwnd, "str", this.propertyName, "ptr")
        }
    }

    Recover() {
        for hwnd in this.GetCandidates() {
            if (DllCall("GetPropW", "ptr", hwnd, "str", this.propertyName, "ptr")) {
                try this.Restore(hwnd)
            } else if (this.claimExisting && this.IsOrphan(hwnd)) {
                ; Repair styling left by a prior manager before adopting the window.
                try this.RepairOrphan(hwnd)
            }
        }
    }

    Clean() {
        idx := 1
        while (idx <= this.windows.Length) {
            if (!WinExist("ahk_id " this.windows[idx])) {
                this.windows.RemoveAt(idx)
                if (this.currentIndex >= idx)
                    this.currentIndex--
            } else if (WinActive("ahk_id " this.windows[idx])) {
                this.currentIndex := idx
                idx++
            } else {
                idx++
            }
        }
        this.currentIndex := this.windows.Length ? Max(1, Min(this.currentIndex, this.windows.Length)) : 0
    }

    IsActive(hwnd) {
        alpha := WinGetTransparent("ahk_id " hwnd)
        return WinActive("ahk_id " hwnd) = hwnd
            && WinGetMinMax("ahk_id " hwnd) != -1
            && (alpha = "" || alpha = 255)
            && !(WinGetExStyle("ahk_id " hwnd) & QuickWindow.ClickThrough)
    }

    Hide(hwnd) {
        WinSetExStyle("+" QuickWindow.ClickThrough, "ahk_id " hwnd)
        WinSetTransparent(0, "ahk_id " hwnd)
    }

    Reveal(hwnd) {
        WinSetExStyle("-" QuickWindow.ClickThrough, "ahk_id " hwnd)
        WinSetTransparent("Off", "ahk_id " hwnd)
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            WinRestore("ahk_id " hwnd)
    }

    Activate(idx) {
        hwnd := this.windows[idx]
        this.Reveal(hwnd)
        WinActivate("ahk_id " hwnd)
        this.currentIndex := idx
    }

    SetManagedTopmost(enabled) {
        if (!this.alwaysOnTop)
            return
        for hwnd in this.windows {
            try {
                if (WinExist("ahk_id " hwnd))
                    WinSetAlwaysOnTop(enabled, "ahk_id " hwnd)
            }
        }
    }

    PositionInitially(hwnd) {
        previous := A_CoordModeMouse
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mouseX, &mouseY)
        CoordMode("Mouse", previous)
        monitor := 1
        loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
            if (mouseX >= left && mouseX < right && mouseY >= top && mouseY < bottom) {
                monitor := A_Index
                break
            }
        }
        MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
        width := Round((right - left) * this.widthRatio)
        height := Round((bottom - top) * this.heightRatio)
        x := Max(left, Min(Round(mouseX - width / 2), right - width))
        y := Max(top, Min(Round(mouseY - height / 2), bottom - height))
        WinMove(x, y, width, height, "ahk_id " hwnd)
    }
}
