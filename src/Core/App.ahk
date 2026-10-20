#Requires AutoHotkey v2.0

; Startup orchestration. Main.ahk calls App.Main(A_Args) after all modules and
; user plugins have been included.
;
; Command-line flags:
;   --config <file>        use this config file instead of <config dir>\config.json
;   --config-dir <dir>     override the config directory (plugins live under it)
;   --check                validate config + plugins, print a report, exit 0/1
;   --sync-plugins         regenerate the plugin include stub and exit (run before
;                          --check after adding or removing plugins)
;   --list-actions         print registered actions as JSON and exit
;   --no-plugin-sync       do not regenerate the plugin include stub
;   --exit-after <ms>      exit automatically (used by end-to-end tests)
class App {
    static Version := "1.0.0"
    static Modules := [AppsModule, QuickWindowsModule, WindowsModule, DesktopModule, DisplayModule]
    static Config := ""
    static ConfigPath := ""
    static Mode := "run"
    static Problems := []
    static _plugins := []
    static _readyHooks := []
    static _explicitConfig := ""
    static _syncPlugins := true
    static _watchStamp := ""
    static _exitAfter := 0
    static _allowVirtualized := false
    static _args := []

    ; ---------------- Plugin API                    ------------------------------

    ; Called from a plugin file at load time:
    ;   App.AddPlugin("myPlugin", (settings) => MyPlugin.Init(settings))
    ; `settings` is the Map at "plugins.<name>" in config (empty when absent).
    ; The init function runs after built-in actions exist and before bindings
    ; are validated, so it can register actions and add bindings.
    static AddPlugin(name, init) {
        App._plugins.Push({ name: name, init: init })
    }

    ; Runs after hotkeys are live (run mode only).
    static OnReady(fn) => App._readyHooks.Push(fn)

    ; ---------------- Startup                       ------------------------------

    static Main(args := unset) {
        App._args := IsSet(args) ? args : []
        App.ParseArgs(App._args)
        if (App.Mode = "run" && !App._allowVirtualized) {
            package := PackageVirtualization.RedirectingPackage()
            if (package != "")
                return App.Fail("hotkit was started inside the " package " app package, which keeps its own "
                    "private copy of the registry and AppData. Settings hotkit changes (tray icons, light/dark theme) "
                    "would not reach Windows.`n`nStart hotkit from Explorer, the Start menu or a "
                    "normal terminal, or pass --allow-virtualized to run anyway.")
        }
        if (App.Mode = "run" && App._syncPlugins && Plugins.Sync()) {
            ; The plugin set changed; restart so the new #Include stub takes effect.
            return App.Restart()
        }
        if (App.Mode = "sync-plugins") {
            changed := Plugins.Sync()
            App.Print("plugins: " Plugins.Discover().Length (changed ? " (stub updated)" : " (stub current)") "`n")
            return ExitApp(0)
        }
        if (App.Mode = "check" && App._syncPlugins && !Plugins.IsCurrent()) {
            ; #Include is resolved before the script runs, so a stale stub means
            ; this process cannot see the current plugin set.
            App.Problems.Push("Plugin list changed since the last run (" Paths.PluginDir()
                "); run with --sync-plugins, then --check again.")
        }
        try {
            App.LoadConfig()
        } catch as e {
            return App.Fail("Could not load config: " e.Message)
        }
        App.Boot()
        if (App.Mode = "check")
            return App.ExitWithReport()
        if (App.Mode = "list-actions")
            return App.ExitWithActions()
        App.Run()
    }

    static ParseArgs(args) {
        i := 1
        while (i <= args.Length) {
            arg := args[i]
            switch arg, false {
                case "--check":
                    App.Mode := "check"
                case "--list-actions":
                    App.Mode := "list-actions"
                case "--sync-plugins":
                    App.Mode := "sync-plugins"
                case "--no-plugin-sync":
                    App._syncPlugins := false
                case "--config":
                    App._explicitConfig := args[++i]
                case "--config-dir":
                    Paths.Override := args[++i]
                case "--exit-after":
                    App._exitAfter := Integer(args[++i])
                case "--allow-virtualized":
                    App._allowVirtualized := true
                default:
                    App.Problems.Push("Unknown argument: " arg)
            }
            i++
        }
    }

    static LoadConfig() {
        path := App._explicitConfig != "" ? Paths.Normalize(App._explicitConfig) : Paths.ConfigFile()
        if (!FileExist(path)) {
            if (App._explicitConfig != "")
                throw Error("Config file not found: " path)
            path := App.Bootstrap(path)
        }
        App.ConfigPath := path
        App.Config := Config.FromFile(path)
    }

    ; First run: copy the example config into the config directory.
    static Bootstrap(path) {
        example := Paths.ExampleConfig()
        if (App.Mode != "run")
            return example
        SplitPath(path, , &dir)
        DirCreate(dir)
        DirCreate(Paths.PluginDir())
        FileCopy(example, path)
        App.OnReady(() => Toast.ShowToast({ fadeDelay: 6000 }, "Created your config:", path))
        return path
    }

    ; Registers actions, initializes plugins, and validates bindings.
    static Boot() {
        cfg := App.Config
        Debugger.Enabled := !!cfg.Get("settings.debug", false)
        Bindings.Reset()
        for p in App.Problems
            Bindings.problems.Push(p)
        App.RegisterCoreActions()
        for m in App.Modules
            m.Register(cfg)
        for p in App._plugins {
            try {
                p.init.Call(cfg.Section("plugins." p.name))
            } catch as e {
                Bindings.problems.Push("plugin '" p.name "': " e.Message)
            }
        }
        Bindings.LoadConfig(cfg)
        Bindings.Validate()
        App.ValidateTray(cfg.List("tray.items"))
        App.Problems := Bindings.problems
    }

    static Run() {
        Persistent()
        cfg := App.Config
        for m in App.Modules {
            if HasMethod(m, "Start") {
                try {
                    m.Start(cfg)
                } catch as e {
                    Bindings.problems.Push(m.Name ": " e.Message)
                }
            }
        }
        Bindings.Apply()
        menus := []
        for m in App.Modules {
            if HasMethod(m, "TrayMenus") {
                for item in m.TrayMenus(cfg)
                    menus.Push(item)
            }
        }
        ShortcutOsd.ConfigPath := App.ConfigPath
        Tray.Build(cfg, menus)
        A_IconTip := "hotkit " App.Version
        if (cfg.Get("settings.watchConfig", true))
            App.WatchConfig()
        if (App._exitAfter > 0)
            SetTimer(() => ExitApp(), -App._exitAfter)
        for fn in App._readyHooks
            try fn.Call()
        if (Bindings.problems.Length) {
            Toast.ShowToast({ color: "FFB000", fadeDelay: 6000 }, "Config problems: " Bindings.problems.Length,
                "Tray › Show Config Problems")
            for p in Bindings.problems
                Debugger.Log(p, "WARN")
        }
    }

    static RegisterCoreActions() {
        reg := (id, fn, desc, params := "") => ActionRegistry.Register(id, fn,
            { module: "core", description: desc, params: params })
        reg("osd.toggle", (*) => ShortcutOsd.Toggle(), "Show or hide the keyboard shortcut overlay")
        reg("app.reload", (*) => App.Restart(), "Reload scripts and config")
        reg("app.exit", (*) => ExitApp(), "Exit hotkit")
        reg("app.openConfigFolder", (*) => Run('explorer.exe "' Paths.ConfigDir() '"'), "Open the config folder")
        reg("app.editConfig", (*) => App.EditConfig(), "Open config.json in the default editor")
        reg("app.showProblems", (*) => App.ShowProblems(), "List config problems")
        reg("bindings.toggleGroup", (name) => App.ToggleGroup(name), "Turn a binding group on or off", "group")
        reg("bindings.enableGroup", (name) => Bindings.SetGroup(name, true), "Turn a binding group on", "group")
        reg("bindings.disableGroup", (name) => Bindings.SetGroup(name, false), "Turn a binding group off", "group")
    }

    ; Like Reload(), but keeps command-line arguments (Reload drops them).
    static Restart() {
        cmd := '"' A_AhkPath '" /restart "' A_ScriptFullPath '"'
        for arg in App._args
            cmd .= ' "' arg '"'
        Run(cmd)
        ExitApp()
    }

    static ToggleGroup(name) {
        enabled := Bindings.ToggleGroup(name)
        group := Bindings.groups[name]
        label := group.description != "" ? group.description : name
        Toast.ShowToast(, label ": " (enabled ? "enabled" : "disabled"))
        Debugger.Log("Binding group " name (enabled ? " enabled" : " disabled"))
    }

    static ValidateTray(items) {
        for item in items {
            if !(item is Map)
                continue
            if (item.Has("items")) {
                App.ValidateTray(item["items"])
                continue
            }
            if (item.Has("action") && !ActionRegistry.Has(item["action"]))
                Bindings.problems.Push("tray item '" MapGet(item, "label", "?") "': unknown action '" item["action"] "'.")
        }
    }

    static EditConfig() {
        try {
            Run('"' App.ConfigPath '"')
        } catch {
            Run('notepad.exe "' App.ConfigPath '"')
        }
    }

    static ShowProblems() {
        text := ""
        for p in Bindings.problems
            text .= "• " p "`n"
        MsgBox(text = "" ? "No problems found." : text, "hotkit: config problems", "Icon!")
    }

    ; Reloads when config.json or the plugin folder changes.
    static WatchConfig() {
        App._watchStamp := App._Stamp()
        SetTimer(() => App._CheckWatch(), 2000)
    }

    static _CheckWatch() {
        stamp := App._Stamp()
        if (stamp != App._watchStamp) {
            App._watchStamp := stamp
            App.Restart()
        }
    }

    static _Stamp() {
        stamp := FileExist(App.ConfigPath) ? FileGetTime(App.ConfigPath, "M") : ""
        for f in Plugins.Discover()
            stamp .= "|" f ":" FileGetTime(f, "M")
        return stamp
    }

    ; ---------------- Non-interactive modes         ------------------------------

    static ExitWithReport() {
        out := "config: " App.ConfigPath "`n"
        out .= "actions: " ActionRegistry.List().Length "`n"
        out .= "bindings: " Bindings.specs.Length "`n"
        out .= "plugins: " App._plugins.Length "`n"
        for p in Bindings.problems
            out .= "problem: " p "`n"
        out .= Bindings.problems.Length ? "FAIL`n" : "OK`n"
        App.Print(out)
        ExitApp(Bindings.problems.Length ? 1 : 0)
    }

    static ExitWithActions() {
        list := []
        for a in ActionRegistry.List()
            list.Push(Map("id", a.id, "module", a.module, "description", a.description, "params", a.params))
        App.Print(JSON.Stringify(list, { pretty: true }) "`n")
        ExitApp(0)
    }

    static Fail(message) {
        if (App.Mode = "run")
            MsgBox(message, "hotkit", "IconX")
        else
            App.Print("error: " message "`n")
        ExitApp(2)
    }

    static Print(text) {
        try FileAppend(text, "*", "UTF-8")
    }
}

; Prints unhandled errors to stdout and exits (used by --check / --list-actions).
HeadlessErrorHandler(err, mode) {
    try FileAppend("error: " err.Message " (" err.File ":" err.Line ")`n" err.Stack "`n", "*", "UTF-8")
    ExitApp(3)
}
