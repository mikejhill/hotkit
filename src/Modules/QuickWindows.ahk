#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\..\Lib\QuickWindow.ahk
#Include %A_LineFile%\..\..\Lib\WindowMatcher.ahk

; Config-defined quick windows. Nothing is predefined; each entry becomes a
; QuickWindow driven by the quickWindow.* actions.
;
;   "quickWindows": {
;     "scratch": {
;       "exe": "notepad.exe",
;       "launch": "notepad.exe",              // command; "{mode}" is replaced by the current mode
;       "modes": [],                          // optional list cycled by quickWindow.cycleMode
;       "match": { "class": "Notepad" },      // WindowMatcher spec (see Lib/WindowMatcher.ahk)
;       "toolWindow": true,                   // hide from taskbar / Alt+Tab while managed
;       "alwaysOnTop": true,
;       "claimExisting": true,                // adopt windows that were already open
;       "multipleWindows": true,              // allow quickWindow.create for extra windows
;       "launchTimeoutSeconds": 10,
;       "size": { "width": 0.5, "height": 0.5 }   // fraction of the work area
;     }
;   }
class QuickWindowsModule {
    static Name := "quickWindows"
    static Instances := Map()
    static Definitions := Map()

    static Register(cfg) {
        QuickWindowsModule.Definitions := cfg.Section("quickWindows")
        reg := (id, method, desc) => ActionRegistry.Register("quickWindow." id,
            (name) => QuickWindowsModule.Get(name).%method%(),
            { module: QuickWindowsModule.Name, description: desc, params: "quick window id" })
        reg("toggle", "Toggle", "Show or hide a quick window (launches if needed)")
        reg("create", "Create", "Open another quick window")
        reg("cycle", "Cycle", "Cycle through a quick window's windows")
        reg("showAll", "ShowAll", "Reveal all of a quick window's windows")
        reg("detach", "Detach", "Release windows back to normal behavior")
        reg("cycleMode", "CycleMode", "Switch a quick window's launch mode")
    }

    ; Instances are created at startup so styles left by a previous run are repaired.
    static Start(cfg) {
        if QuickWindowsModule.Definitions.Count
            FocusHistory.Start()  ; reveals hidden quick windows activated from the taskbar
        for name in QuickWindowsModule.Definitions {
            try {
                QuickWindowsModule.Get(name)
            } catch as e {
                Bindings.problems.Push("quickWindows." name ": " e.Message)
            }
        }
    }

    static Get(name) {
        if QuickWindowsModule.Instances.Has(name)
            return QuickWindowsModule.Instances[name]
        if !QuickWindowsModule.Definitions.Has(name)
            throw ValueError("Unknown quick window '" name "'. Define it under `"quickWindows`" in your config.")
        qw := QuickWindowsModule.Build(name, QuickWindowsModule.Definitions[name])
        QuickWindowsModule.Instances[name] := qw
        return qw
    }

    static Build(name, def) {
        exe := MapGet(def, "exe", "")
        launch := MapGet(def, "launch", "")
        if (exe = "" || launch = "")
            throw ValueError("needs `"exe`" and `"launch`".")
        size := MapGet(def, "size", Map())
        options := Map(
            "modes", MapGet(def, "modes", []),
            "toolWindow", !!MapGet(def, "toolWindow", false),
            "alwaysOnTop", !!MapGet(def, "alwaysOnTop", false),
            "claimExisting", !!MapGet(def, "claimExisting", false),
            "multipleWindows", !!MapGet(def, "multipleWindows", false),
            "launchTimeoutSeconds", MapGet(def, "launchTimeoutSeconds", 10),
            "widthRatio", MapGet(size, "width", 0.5),
            "heightRatio", MapGet(size, "height", 0.5))
        isTarget := WindowMatcher.Predicate(MapGet(def, "match", Map()))
        launcher := (manager, *) => Run(QuickWindowsModule.LaunchCommand(launch, manager.CurrentMode()))
        return QuickWindow(name, exe, launcher, isTarget, options)
    }

    ; Pure: substitutes the current mode into the launch command.
    static LaunchCommand(template, mode) {
        cmd := Paths.Expand(template)
        if InStr(cmd, "{mode}")
            return Trim(StrReplace(cmd, "{mode}", mode))
        return mode = "" ? cmd : cmd " " mode
    }
}
