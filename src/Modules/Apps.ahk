#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\..\Lib\AppUtil.ahk

; Generic launch / focus / send actions. Which apps exist is user config:
;
;   "apps": {
;     "notes": {
;       "name": "Notepad",                    // toast label
;       "run": "notepad.exe",                 // command line passed to Run
;       "match": "ahk_exe notepad.exe",       // WinTitle (RegEx title match mode)
;       "options": ""                         // Run options: Min, Max, Hide
;     }
;   }
;
; app.toggle activates the app's window, minimizes it if already active, or
; launches it when no window exists. app.cycle switches between the app's
; windows (most recent first, then rotating) and launches it when none exist.
class AppsModule {
    static Name := "apps"
    static Apps := Map()

    static Register(cfg) {
        AppsModule.Apps := cfg.Section("apps")
        reg := (id, fn, desc, params := "") => ActionRegistry.Register(id, fn,
            { module: AppsModule.Name, description: desc, params: params })

        reg("app.toggle", (id) => AppsModule.Toggle(id), "Focus, minimize, or launch an app", "app id")
        reg("app.cycle", (id) => AppsModule.Toggle(id, true), "Switch between an app's windows, or launch it", "app id")
        reg("app.launch", (id) => AppsModule.Launch(id), "Launch an app", "app id")
        reg("run", (command, options := "", workingDir := "") => Run(Paths.Expand(command), Paths.Expand(workingDir), options),
            "Run a command line", "command, [options], [workingDir]")
        reg("run.wait", (command, options := "", workingDir := "") => RunWait(Paths.Expand(command), Paths.Expand(workingDir), options),
            "Run a command line and wait for it", "command, [options], [workingDir]")
        reg("send", (keys) => Send(keys), "Send keystrokes (AutoHotkey Send syntax)", "keys")
        reg("sendText", (text) => SendText(text), "Type literal text", "text")
        reg("hotkey.trigger", (hk) => AppUtil.RunHotkey(hk), "Trigger another hotkey by its notation", "hotkey")
    }

    static Start(cfg) {
        FocusHistory.Start()
    }

    static Get(id) {
        if !AppsModule.Apps.Has(id)
            throw ValueError("Unknown app '" id "'. Define it under `"apps`" in your config.")
        app := AppsModule.Apps[id]
        if !(app is Map) || !app.Has("run")
            throw ValueError("App '" id "' needs a `"run`" command.")
        return app
    }

    static Toggle(id, cycle := false) {
        app := AppsModule.Get(id)
        match := MapGet(app, "match", "")
        if (match = "")
            return AppsModule.Launch(id)
        options := MapGet(app, "options", "")
        AppUtil.OpenApp(MapGet(app, "name", id), Paths.Expand(app["run"]), match, options != "" ? options : unset, cycle)
    }

    static Launch(id) {
        app := AppsModule.Get(id)
        options := MapGet(app, "options", "")
        AppUtil.LaunchApp(MapGet(app, "name", id), Paths.Expand(app["run"]), options != "" ? options : unset)
    }
}
