#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\..\Lib\WindowUtil.ahk
#Include %A_LineFile%\..\..\Lib\Toast.ahk

; Window actions, a last-active-window switcher, and window rules.
;
;   "modules": {
;     "alwaysOnTop": { "indicatorColor": "4F8CC9" },    // border color; "" to disable
;     "taskSwitcher": {
;       "ignore": [ { "exe": "SomeWrapper.exe", "emptyTitle": true } ]
;     },
;     "windowRules": {
;       "pollMs": 250,
;       "rules": [ { "match": "ahk_exe SomeApp.exe", "alwaysOnTop": false } ]
;     }
;   }
class WindowsModule {
    static Name := "windows"
    static IndicatorColor := "4F8CC9"
    static Ignore := []
    static Rules := []
    static _ruleTimer := 0

    static Register(cfg) {
        WindowsModule.IndicatorColor := cfg.Get("modules.alwaysOnTop.indicatorColor", "4F8CC9")
        WindowsModule.Ignore := cfg.List("modules.taskSwitcher.ignore")
        WindowsModule.Rules := cfg.List("modules.windowRules.rules")
        reg := (id, fn, desc, params := "") => ActionRegistry.Register(id, fn,
            { module: WindowsModule.Name, description: desc, params: params })

        reg("window.toggleAlwaysOnTop", (*) => WindowsModule.ToggleAlwaysOnTop(), "Pin or unpin the active window")
        reg("window.toggleMinimized", (*) => WindowUtil.ToggleActiveWindowMinimized(),
            "Minimize the active window, or restore the last one minimized")
        reg("window.sendBackward", (*) => WindowsModule.MoveInZOrder("backward"),
            "Send the active window behind the next window it overlaps (keeps focus)")
        reg("window.sendToBack", (*) => WindowsModule.MoveInZOrder("back"),
            "Send the active window behind all other windows (keeps focus)")
        reg("window.bringForward", (*) => WindowsModule.MoveInZOrder("forward"),
            "Bring the active window in front of the next window it overlaps")
        reg("window.bringToFront", (*) => WindowsModule.MoveInZOrder("front"),
            "Bring the active window in front of all other windows")
        reg("window.cycleNext", (*) => WindowsModule.Restack((*) => WindowsModule.Cycle("next")),
            "Focus the next window, like Alt+Tab; with a modifier, repeat while holding it")
        reg("window.cyclePrevious", (*) => WindowsModule.Restack((*) => WindowsModule.Cycle("previous")),
            "Focus the previous window, like Shift+Alt+Tab; with a modifier, repeat while holding it")
        reg("window.focusNext", (*) => WindowUtil.FocusNextWindow(), "Focus the next window in z-order")
        reg("window.activateLast", (winTitle := "") => WindowsModule.ActivateLast(winTitle),
            "Activate the most recent other window (optionally matching a WinTitle)", "[winTitle]")
        reg("taskView.open", (*) => Run("shell:::{3080F90E-D7AD-11D9-BD98-0000947B0257}"), "Open Windows Task View")
    }

    static Start(cfg) {
        if (WindowsModule.Rules.Length && cfg.ModuleEnabled("windowRules", true)) {
            WindowsModule._ruleTimer := (*) => WindowsModule.ApplyRules()
            SetTimer(WindowsModule._ruleTimer, cfg.Get("modules.windowRules.pollMs", 250))
        }
    }

    static ToggleAlwaysOnTop() {
        ; Capture once so a focus change cannot redirect the operation.
        hwnd := WinExist("A")
        if (!hwnd)
            return
        try {
            enabled := WindowUtil.ToggleAlwaysOnTop(hwnd)
        } catch as e {
            return Toast.ShowToast({ color: "Red", fadeDelay: 5000 }, "Always on Top:", e.Message)
        }
        if (WindowsModule.IndicatorColor != "") {
            try {
                if (enabled)
                    WindowUtil.AddAlwaysOnTopIndicator(hwnd, WindowsModule.IndicatorColor)
                else
                    WindowUtil.RemoveAlwaysOnTopIndicator(hwnd)
            } catch as e {
                return Toast.ShowToast({ color: "Red", fadeDelay: 5000 }, "Always on Top:",
                    (enabled ? "Enabled" : "Disabled") " (border update failed)`n" e.Message)
            }
        }
        Toast.ShowToast(, "Always on Top:", enabled ? "Enabled" : "Disabled")
    }

    ; Focus cycling, like holding Alt for Alt+Tab: bound with a modifier, the
    ; window order is captured at the first press and kept while the modifier stays
    ; held, so each press only changes which window is raised and focused.
    ; Releasing the key ends the session and leaves the selection in front.
    ; Without a modifier every press is its own session.
    static _cycle := ""
    static _cyclePoll := (*) => WindowsModule.PollCycle()

    static Cycle(direction) {
        session := WindowsModule._cycle
        if (!session) {
            session := WindowUtil.CycleSnapshot()
            session.keys := WindowsModule.CycleHoldKeys(Bindings.specs, Bindings.modifiers, A_ThisHotkey,
                WindowsModule._ContextActive)
        }
        WindowUtil.CycleStep(session, direction)
        if (WindowsModule.AnyDown(session.keys)) {
            WindowsModule._cycle := session
            SetTimer(WindowsModule._cyclePoll, 30)
        } else {
            WindowsModule.EndCycle()
        }
    }

    static PollCycle() {
        session := WindowsModule._cycle
        if (!session || !WindowsModule.AnyDown(session.keys))
            WindowsModule.EndCycle()
    }

    static EndCycle() {
        SetTimer(WindowsModule._cyclePoll, 0)
        WindowsModule._cycle := ""
    }

    ; True when the binding's modifier/layer/group/window conditions hold now,
    ; i.e. it is the variant of the hotkey that just fired.
    static _ContextActive := (spec) => (fn := Bindings._Context(spec)) = "" || fn()

    static AnyDown(keys) {
        for k in keys {
            if GetKeyState(k, "P")
                return true
        }
        return false
    }

    ; Pure: modifier keys of the cycle bindings registered on hotkey whose
    ; context isActive reports as live (the binding that fired), i.e. the keys
    ; whose release ends a session; empty without a modifier.
    static CycleHoldKeys(specs, modifiers, hotkey, isActive := (*) => true) {
        isCycle := (a) => a = "window.cycleNext" || a = "window.cyclePrevious"
        keys := []
        for spec in specs {
            if (spec.keys != hotkey || spec.modifier = "" || !modifiers.Has(spec.modifier) || !isActive(spec))
                continue
            found := spec.HasOwnProp("action") && isCycle(spec.action)
            ; Gesture bindings keep their actions under tap/doubleTap/hold.
            if (!found && spec.HasOwnProp("gestures") && IsObject(spec.gestures)) {
                for name in ["tap", "doubleTap", "hold"] {
                    ref := spec.gestures.HasOwnProp(name) ? spec.gestures.%name% : ""
                    if (IsObject(ref) && isCycle(ref.action))
                        found := true
                }
            }
            if (found)
                keys.Push(modifiers[spec.modifier].key)
        }
        return keys
    }

    static Restack(fn) {
        try {
            fn()
        } catch TargetError {
            return
        } catch as e {
            Toast.ShowToast({ color: "Red", fadeDelay: 5000 }, "Window order:", e.Message)
        }
    }

    static MoveInZOrder(direction) {
        try {
            WindowUtil.MoveInZOrder(direction)
        } catch TargetError {
            return
        } catch as e {
            Toast.ShowToast({ color: "Red", fadeDelay: 5000 }, "Window order:", e.Message)
        }
    }

    static ActivateLast(winTitle := "") {
        hwnd := WindowsModule.FindLast(winTitle)
        if (hwnd) {
            WinActivate(hwnd)
            WinMoveTop(hwnd)
        }
    }

    ; Most recent window in z-order other than the active one, skipping tool
    ; windows and anything matched by the ignore list.
    static FindLast(winTitle := "") {
        active := WinExist("A")
        for hwnd in (winTitle = "" ? WinGetList() : WinGetList(winTitle)) {
            if (hwnd = active)
                continue
            info := {
                exStyle: WinGetExStyle(hwnd),
                exe: WinGetProcessName(hwnd),
                title: WinGetTitle(hwnd),
            }
            if WindowsModule.IsSwitchable(info, WindowsModule.Ignore)
                return hwnd
        }
        return 0
    }

    ; Pure: decides whether a window snapshot is eligible for switching.
    static IsSwitchable(info, ignore) {
        if (info.exStyle & 0x80)  ; WS_EX_TOOLWINDOW
            return false
        for rule in ignore {
            if (MapGet(rule, "exe", "") != "" && info.exe != rule["exe"])
                continue
            if (MapGet(rule, "emptyTitle", false) && info.title != "")
                continue
            if (MapGet(rule, "title", "") != "" && !RegExMatch(info.title, rule["title"]))
                continue
            return false
        }
        return true
    }

    ; Enforces rules such as "never always-on-top" on matching windows. Windows
    ; are only touched when their state differs, since some apps re-activate
    ; themselves on every SetWindowPos.
    static ApplyRules() {
        for rule in WindowsModule.Rules {
            match := MapGet(rule, "match", "")
            if (match = "" || !rule.Has("alwaysOnTop"))
                continue
            for hwnd in WinGetList(match) {
                try {
                    isTop := !!(WinGetExStyle(hwnd) & 0x8)
                    if (isTop != !!rule["alwaysOnTop"])
                        WinSetAlwaysOnTop(!!rule["alwaysOnTop"], hwnd)
                }
            }
        }
    }
}
