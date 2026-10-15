#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\..\Lib\DisplayBrightness.ahk
#Include %A_LineFile%\..\..\Lib\DisplayScale.ahk

; Brightness (hardware, gamma, Night Light) and display scaling actions.
;
; Config:
;   "modules": {
;     "displayBrightness": { "step": 10, "swapFallback": 85,
;                            "gamma": { "min": 25, "max": 300, "default": 85 } },
;     "displayScale": { "setDpiPath": "%USERPROFILE%\\Tools\\SetDpi.exe",
;                       "presets": [100, 125, 150, 175, 200], "debounceMs": 500 }
;   }
class DisplayModule {
    static Name := "display"
    static BrightnessEnabled := false
    static ScaleEnabled := false

    static Register(cfg) {
        DisplayModule._RegisterBrightness(cfg)
        DisplayModule._RegisterScale(cfg)
    }

    static Start(cfg) {
        if (DisplayModule.BrightnessEnabled) {
            ; Start from a neutral ramp so a crashed session cannot leave the screen dimmed.
            GammaBrightness.Reset()
            OnExit((*) => GammaBrightness.Reset())
        }
    }

    static _RegisterBrightness(cfg) {
        DisplayModule.BrightnessEnabled := cfg.ModuleEnabled("displayBrightness")
        s := cfg.Section("modules.displayBrightness")
        step := MapGet(s, "step", 10)
        HardwareBrightness.SwapFallback := MapGet(s, "swapFallback", 85)
        gamma := MapGet(s, "gamma", Map())
        GammaBrightness.Min := MapGet(gamma, "min", 25.0)
        GammaBrightness.Max := MapGet(gamma, "max", 300.0)
        GammaBrightness.DefaultSaved := MapGet(gamma, "default", 85.0)
        GammaBrightness.Saved := GammaBrightness.DefaultSaved
        m := { module: "displayBrightness" }
        reg := (id, fn, desc, params := "") => ActionRegistry.Register(id, fn,
            { module: m.module, description: desc, params: params })

        reg("brightness.increase", (*) => HardwareBrightness.Adjust(step), "Increase monitor brightness")
        reg("brightness.decrease", (*) => HardwareBrightness.Adjust(-step), "Decrease monitor brightness")
        reg("brightness.adjust", (delta) => HardwareBrightness.Adjust(delta), "Adjust monitor brightness", "delta")
        reg("brightness.set", (value) => HardwareBrightness.Set(value), "Set monitor brightness", "percent")
        reg("brightness.swap", (target) => HardwareBrightness.Swap(target),
            "Toggle brightness between a level and the last used level", "target percent")
        reg("brightness.setExternal", (value) => DDCCIController.SetBrightness(value),
            "Set external (DDC/CI) monitor brightness", "percent")
        reg("brightness.adjustExternal", (delta) => DDCCIController.AdjustBrightness(delta),
            "Adjust external (DDC/CI) monitor brightness", "delta")
        reg("monitors.refresh", (*) => DDCCIController.RefreshMonitorList(), "Re-detect monitors")
        reg("gamma.increase", (*) => GammaBrightness.Step(1), "Increase software (gamma) brightness")
        reg("gamma.decrease", (*) => GammaBrightness.Step(-1), "Decrease software (gamma) brightness")
        reg("gamma.toggle", (*) => GammaBrightness.Toggle(), "Toggle software (gamma) brightness")
        reg("gamma.set", (value) => GammaBrightness.Set(value), "Set software (gamma) brightness", "percent")
        reg("nightLight.toggle", (*) => NightLight.Toggle(), "Toggle Windows Night Light")
        reg("nightLight.increase", (*) => NightLight.Adjust(5), "Increase Night Light strength")
        reg("nightLight.decrease", (*) => NightLight.Adjust(-5), "Decrease Night Light strength")
        reg("nightLight.set", (value) => NightLight.Set(value), "Set Night Light strength", "percent")
    }

    static _RegisterScale(cfg) {
        DisplayModule.ScaleEnabled := cfg.ModuleEnabled("displayScale")
        s := cfg.Section("modules.displayScale")
        DisplayScale.SetDpiPath := Paths.Expand(MapGet(s, "setDpiPath", ""))
        presets := MapGet(s, "presets", "")
        if (presets is Array && presets.Length)
            DisplayScale.Presets := presets
        DisplayScale.DebounceMs := MapGet(s, "debounceMs", 500)
        reg := (id, fn, desc, params := "") => ActionRegistry.Register(id, fn,
            { module: "displayScale", description: desc, params: params })
        reg("displayScale.increase", (monitor := "") => DisplayScale.Increase(monitor), "Increase display scale", "[monitor]")
        reg("displayScale.decrease", (monitor := "") => DisplayScale.Decrease(monitor), "Decrease display scale", "[monitor]")
        reg("displayScale.show", (monitor := "") => DisplayScale.ShowCurrent(monitor), "Show display scale", "[monitor]")
        reg("displayScale.set", (scale, monitor := "") => DisplayScale.Apply(scale, monitor), "Set display scale", "percent, [monitor]")
    }

    static TrayMenus(cfg) {
        menus := []
        if (DisplayModule.BrightnessEnabled) {
            ddc := Menu()
            for value in [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
                ddc.Add(value "%", ActionRegistry.Callback(Map("action", "brightness.set", "args", [value])))
            night := Menu()
            night.Add("Toggle &Night Light", ActionRegistry.Callback("nightLight.toggle"))
            night.Add()
            for value in [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
                night.Add("Strength: " value "%", ActionRegistry.Callback(Map("action", "nightLight.set", "args", [value])))
            gamma := Menu()
            for value in [25, 50, 75, 85, 100, 125, 150, 175, 200, 250, 300]
                gamma.Add(value "%", ActionRegistry.Callback(Map("action", "gamma.set", "args", [value])))
            root := Menu()
            root.Add("Hardware &Brightness", ddc)
            root.Add("&Night Light", night)
            root.Add("&Gamma Brightness", gamma)
            root.Add()
            root.Add("&Refresh Monitors", ActionRegistry.Callback("monitors.refresh"))
            menus.Push({ label: "Display &Brightness", menu: root })
        }
        if (DisplayModule.ScaleEnabled) {
            scale := Menu()
            scale.Add("&Show Current Scale", ActionRegistry.Callback("displayScale.show"))
            scale.Add("&Decrease Scale", ActionRegistry.Callback("displayScale.decrease"))
            scale.Add("&Increase Scale", ActionRegistry.Callback("displayScale.increase"))
            scale.Add()
            for value in DisplayScale.SortNumeric(DisplayScale.Presets)
                scale.Add("&" value "%", ActionRegistry.Callback(Map("action", "displayScale.set", "args", [value])))
            menus.Push({ label: "Display &Scale", menu: scale })
        }
        return menus
    }
}
