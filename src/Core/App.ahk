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
    static Version := "1.23.0"
    static Modules := [AppsModule, QuickWindowsModule, WindowsModule, DesktopModule, DisplayModule, PowerModule]
    static Config := ""
    static ConfigPath := ""
    static Mode := "run"
    static Problems := []
    static _plugins := []
    static _readyHooks := []
    static _explicitConfig := ""
    static _syncPlugins := true
    static _watchStamp := ""
    static _pendingStamp := ""
    static _exitAfter := 0
    static _allowVirtualized := false
    static _args := []
    ; True when this process was started by App.Restart (a reload).
    static Restarted := false

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
        App.Restarted := EnvGet("HOTKIT_RESTARTED") = "1"
        EnvSet("HOTKIT_RESTARTED")
        ; App.Restart names the process it replaces; let it finish exiting
        ; before taking over hotkeys.
        previous := EnvGet("HOTKIT_RESTART_PID")
        EnvSet("HOTKIT_RESTART_PID")
        if (previous != "" && IsInteger(previous))
            ProcessWaitClose(Integer(previous), 10)
        App.ParseArgs(App._args)
        if (App.Mode = "run" && EnvGet("HOTKIT_HEADLESS") != "1")
            App.ReplaceOtherInstances()
        if Tray.ShowsIcon(App.Mode, EnvGet("HOTKIT_HEADLESS") = "1")
            A_IconHidden := false
        if (App.Mode = "run") {
            OnError((err, mode) => StatusLog.OnError(err, mode))
            StatusLog.Start(App._explicitConfig != "" ? Paths.Normalize(App._explicitConfig) : Paths.ConfigFile())
        }
        if (App.Mode = "run" && !App._allowVirtualized) {
            package := PackageVirtualization.RedirectingPackage()
            if (package != "")
                return App.Fail("Hotkit was started inside the " package " app package, which keeps its own "
                    "private copy of the registry and AppData. Settings Hotkit changes (tray icons, light/dark theme) "
                    "would not reach Windows.`n`nStart Hotkit from Explorer, the Start menu or a "
                    "normal terminal, or pass --allow-virtualized to run anyway.")
        }
        if (App.Mode = "run" && App._syncPlugins && Plugins.Sync()) {
            ; The plugin set changed; restart so the new #Include stub takes effect.
            return App.Restart(App.Restarted)
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

    ; Like #SingleInstance Force, but only for interactive runs: closes other
    ; Hotkit instances started from this same script, letting their OnExit
    ; cleanup run.
    static ReplaceOtherInstances() {
        hidden := DetectHiddenWindows(true)
        try {
            for hwnd in WinGetList("ahk_class AutoHotkey") {
                if (hwnd = A_ScriptHwnd)
                    continue
                try {
                    if !Paths.IsInstanceTitle(WinGetTitle(hwnd), A_ScriptFullPath)
                        continue
                    pid := WinGetPID(hwnd)
                    WinClose(hwnd)
                    ; Exit schedules may still be running; wait for them.
                    if ProcessWaitClose(pid, 15) {
                        DetectHiddenWindows(hidden)
                        return App.Fail("Another Hotkit from this folder (PID " pid ") didn't exit, so this one "
                            "won't start. Exit it from its tray icon or Task Manager, then start Hotkit again.")
                    }
                }
            }
        } finally {
            DetectHiddenWindows(hidden)
        }
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
        if (App.Mode = "run") {
            SplitPath(path, , &dir)
            if (dir = "")
                dir := A_WorkingDir
            ; A copy of the schema next to the config, matching this version, lets
            ; editors use "$schema": "./config.schema.json" with no network access
            ; (VS Code asks before loading a schema from an untrusted web domain).
            ; A file of that name that isn't a hotkit schema is left alone.
            target := dir "\config.schema.json"
            try {
                if (target = path || (FileExist(target) && !Paths.IsHotkitSchema(target)))
                    StatusLog.Warn("not updating " target ": it isn't a hotkit schema copy")
                else
                    Paths.SyncCopy(Paths.Schema(), target)
            } catch as e {
                StatusLog.Warn("could not copy config.schema.json: " e.Message)
            }
        }
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
        App.OnReady(() => Toast.ShowToast({ fadeDelay: 6000 }, "Created Your Config:", path))
        return path
    }

    ; Registers actions, initializes plugins, and validates bindings.
    static Boot() {
        cfg := App.Config
        Debugger.Enabled := !!cfg.Get("settings.debug", false)
        Bindings.Reset()
        Schedules.Reset(Bindings.problems)
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
        Schedules.LoadConfig(cfg)
        Schedules.Validate()
        App.ValidateTray(cfg.List("tray.items"))
        Updates.Configure(cfg, Bindings.problems)
        iconProblem := Tray.ResolveIcon(cfg).problem
        if (iconProblem != "")
            Bindings.problems.Push(iconProblem)
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
        App.RestoreLayer()
        Bindings.ignoreSimulated := !!cfg.Get("settings.ignoreSimulatedKeys", true)
        Bindings.Apply()
        ; After Apply: AutoHotkey's keyboard hook must exist before ours. Remote
        ; sessions also use its record of the latest key (see RemoteSessions).
        ; It also sees Win when a remote session client takes it first (see
        ; Bindings.InterceptKey).
        SimulatedKeys.Intercept := (vk, sc, up, injected) => Bindings.InterceptKey(vk, sc, up, injected)
        if (Bindings.ignoreSimulated || Bindings.remoteWindows.Length || Bindings.HasWinChords()) {
            try {
                SimulatedKeys.Enable()
                if (SimulatedKeys.problem != "")
                    Bindings.problems.Push(SimulatedKeys.problem)
            } catch as e {
                Bindings.problems.Push("Couldn't watch for simulated keys, so programs can trigger shortcuts: " e.Message)
            }
        }
        ; After SimulatedKeys: re-installing hooks for a remote session keeps that order.
        try {
            RemoteSessions.Start(Bindings.remoteWindows, Bindings.RemoteModifiers())
        } catch as e {
            Bindings.problems.Push("Couldn't watch for remote session windows, so their clients may take keys first: " e.Message)
        }
        try {
            SuspendWindows.OnChange := (*) => Tray.RefreshTip()
            SuspendWindows.EndPending := () => Bindings.EndPending()
            SuspendWindows.Start(Bindings.suspendWindows, Map(
                "CapsLock", cfg.Get("settings.keyboard.capsLock", ""),
                "NumLock", cfg.Get("settings.keyboard.numLock", "")),
                !!cfg.Get("settings.keyboard.keepWhileSuspended", false))
        } catch as e {
            Bindings.problems.Push("Couldn't watch for settings.suspendWhenActive windows: " e.Message)
        }
        ; Before Tray.Build, so a problem here gets the tray's problems item.
        try {
            Schedules.Start()
        } catch as e {
            Bindings.problems.Push("schedules: " e.Message)
        }
        menus := []
        for m in App.Modules {
            if HasMethod(m, "TrayMenus") {
                for item in m.TrayMenus(cfg)
                    menus.Push(item)
            }
        }
        ShortcutOsd.ConfigPath := App.ConfigPath
        Tray.Build(cfg, menus)
        Tray.Version := App.Version
        Tray.AddStatus(() => Bindings.activeLayer != "" ? Bindings.layers[Bindings.activeLayer].label : "")
        Tray.AddStatus(() => SuspendWindows.active ? "Paused While This Window Is Active" : "")
        Tray.AddStatus(() => Updates.Status(Updates.Available))
        Updates.Version := App.Version
        Updates.RepoDir := Paths.RepoRoot()
        Updates.OnRestart := () => App.Restart()
        Updates.Start(A_TrayMenu, "Open &Config Folder")
        Tray.RefreshTip()
        if (cfg.Get("settings.watchConfig", true))
            App.WatchConfig()
        if (App._exitAfter > 0)
            SetTimer(() => ExitApp(), -App._exitAfter)
        for fn in App._readyHooks
            try fn.Call()
        Schedules.Fire(App.Restarted ? "reload" : "startup")
        if (Bindings.problems.Length) {
            Toast.ShowToast({ color: "FFB000", fadeDelay: 6000 }, "Config Problems: " Bindings.problems.Length,
                "Tray › Show Config Problems")
            for p in Bindings.problems {
                Debugger.Log(p, "WARN")
                StatusLog.Warn("problem: " p)
            }
        }
        StatusLog.Info("ready, " Bindings.problems.Length " problem(s)")
    }

    static RegisterCoreActions() {
        reg := (id, fn, desc, params := "") => ActionRegistry.Register(id, fn,
            { module: "core", description: desc, params: params })
        reg("osd.toggle", (*) => ShortcutOsd.Toggle(), "Show or hide the keyboard shortcut overlay")
        reg("app.reload", (*) => App.Restart(), "Reload scripts and config")
        reg("app.exit", (*) => ExitApp(), "Exit Hotkit")
        reg("app.openConfigFolder", (*) => Run('explorer.exe "' Paths.ConfigDir() '"'), "Open the config folder")
        reg("app.editConfig", (*) => App.EditConfig(), "Open config.json in the default editor")
        reg("app.showProblems", (*) => App.ShowProblems(), "List config problems")
        reg("app.checkForUpdates", (*) => Updates.Check(true), "Check GitHub for a newer Hotkit release")
        reg("schedule.run", (name) => Schedules.RunNow(name), "Run a schedule's action now", "name")
        reg("app.update", (*) => Updates.Install(), "Install the newer Hotkit release and reload (checks first if none is known)")
        reg("bindings.toggleGroup", (name) => App.ToggleGroup(name), "Turn a binding group on or off", "group")
        reg("bindings.enableGroup", (name) => Bindings.SetGroup(name, true), "Turn a binding group on", "group")
        reg("bindings.disableGroup", (name) => Bindings.SetGroup(name, false), "Turn a binding group off", "group")
        reg("layer.activate", (name) => App.ActivateLayer(name), "Switch to a layer", "layer")
        reg("layer.next", (*) => App.StepLayer(1), "Switch to the next layer")
        reg("layer.previous", (*) => App.StepLayer(-1), "Switch to the previous layer")
    }

    ; ---------------- Layers                        ------------------------------

    ; Switches the active layer, remembers it across restarts, and shows it.
    static ActivateLayer(name) {
        try {
            name := Bindings.SetLayer(name)
        } catch ValueError as e {
            Toast.ShowToast({ color: "FF6060", fadeDelay: 3000 }, "Layer:", e.Message)
            return
        }
        App.SaveState()
        Tray.UpdateLayers()
        Tray.RefreshTip()
        if ShortcutOsd.IsOpen()
            ShortcutOsd.Refresh()
        layer := Bindings.layers[name]
        if (layer.description != "")
            Toast.ShowToast(, layer.label, layer.description)
        else
            Toast.ShowToast(, layer.label)
        StatusLog.Info("layer: " name)
    }

    static StepLayer(step) {
        if (!Bindings.layerOrder.Length)
            return Toast.ShowToast({ color: "FF6060", fadeDelay: 3000 }, "Layer:", "No layers defined")
        App.ActivateLayer(Bindings.StepLayer(Bindings.layerOrder, Bindings.activeLayer, step))
    }

    ; Goes back to the layer that was active before the last restart (config
    ; saves restart the app), when it still exists.
    static RestoreLayer() {
        name := MapGet(App.LoadState(), "layer", "")
        if (name != "" && !IsObject(name) && Bindings.layers.Has(String(name)))
            Bindings.SetLayer(name)
    }

    static LoadState() {
        try {
            path := Paths.StateFile()
            if FileExist(path) {
                state := Config.FromFile(path).data
                if (state is Map)
                    return state
            }
        }
        return Map()
    }

    static SaveState() {
        try {
            path := Paths.StateFile()
            SplitPath(path, , &dir)
            DirCreate(dir)
            f := FileOpen(path, "w", "UTF-8-RAW")
            f.Write(JSON.Stringify(Map("layer", Bindings.activeLayer)))
            f.Close()
        } catch as e {
            StatusLog.Warn("could not save state: " e.Message)
        }
    }

    ; Like Reload(), but keeps command-line arguments (Reload drops them).
    ; Modules with a BeforeRestart method can hand state to the new process.
    ; The new process sees App.Restarted (schedules fire "reload", not
    ; "startup"), and this one doesn't fire "exit".
    static Restart(reload := true) {
        Schedules.Restarting := true
        if (reload)
            EnvSet("HOTKIT_RESTARTED", "1")
        else
            EnvSet("HOTKIT_RESTARTED")
        EnvSet("HOTKIT_RESTART_PID", ProcessExist())
        for m in App.Modules {
            if HasMethod(m, "BeforeRestart")
                try m.BeforeRestart()
        }
        ; No /restart: AutoHotkey would close every instance of this script with
        ; it, including an interactive one when a headless test run restarts.
        cmd := '"' A_AhkPath '" "' A_ScriptFullPath '"'
        for arg in App._args
            cmd .= ' "' arg '"'
        Run(cmd)
        ExitApp()
    }

    static ToggleGroup(name) {
        enabled := Bindings.ToggleGroup(name)
        group := Bindings.groups[name]
        label := group.description != "" ? group.description : name
        Toast.ShowToast(, label ": " (enabled ? "Enabled" : "Disabled"))
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
        MsgBox(text = "" ? "No problems found." : text, "Hotkit: Config Problems", "Icon!")
    }

    ; Reloads when config.json or the plugin folder changes. A change is applied
    ; only after it has stayed the same for one poll (so a save in progress is
    ; not read half-written) and config.json still parses; otherwise the running
    ; config is kept and the error goes to a toast and the status log.
    static WatchConfig() {
        App._watchStamp := App._Stamp()
        SetTimer(() => App._CheckWatch(), 2000)
    }

    static _CheckWatch() {
        stamp := App._Stamp()
        if (stamp = App._watchStamp) {
            App._pendingStamp := ""
            return
        }
        if (stamp != App._pendingStamp) {
            App._pendingStamp := stamp
            return
        }
        App._pendingStamp := ""
        App._watchStamp := stamp
        try {
            Config.FromFile(App.ConfigPath)
        } catch as e {
            StatusLog.Error("config change not applied, keeping the running config: " e.Message)
            Toast.ShowToast({ color: "FF6060", fadeDelay: 8000 }, "Config Not Reloaded:", e.Message)
            return
        }
        StatusLog.Info("config changed, restarting")
        App.Restart()
    }

    static _Stamp() {
        stamp := FileExist(App.ConfigPath) ? FileGetTime(App.ConfigPath, "M") ":" FileGetSize(App.ConfigPath) : ""
        for f in Plugins.Discover()
            stamp .= "|" f ":" FileGetTime(f, "M") ":" FileGetSize(f)
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
        if (App.Mode = "run") {
            StatusLog.Error(message)
            MsgBox(message, "Hotkit", "IconX")
        }
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
