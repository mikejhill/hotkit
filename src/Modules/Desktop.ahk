#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\..\Lib\ThemeFunctions.ahk
#Include %A_LineFile%\..\..\Lib\WallpaperFunctions.ahk
#Include %A_LineFile%\..\..\Lib\JSON.ahk
#Include %A_LineFile%\..\..\Lib\Toast.ahk

; Theme, wallpaper, media, keyboard-lock, tray-icon, and PowerToys actions.
;
;   "settings": { "keyboard": { "capsLock": "AlwaysOff", "numLock": "AlwaysOn" } },
;   "modules": {
;     "theme": {
;       "wallpaper": { "light": "bing", "dark": "%USERPROFILE%\\Pictures\\dark.png" },
;       "bing": { "cacheDir": "%LOCALAPPDATA%\\BingWallpapers", "maxAgeDays": 5 }
;     },
;     "trayIcons": { "enabled": true, "intervalSeconds": 60 }
;   }
class DesktopModule {
    static Name := "desktop"
    static Wallpaper := Map()
    static Bing := Map()

    static Register(cfg) {
        DesktopModule.Wallpaper := cfg.Section("modules.theme.wallpaper")
        DesktopModule.Bing := cfg.Section("modules.theme.bing")
        reg := (id, fn, desc, params := "") => ActionRegistry.Register(id, fn,
            { module: DesktopModule.Name, description: desc, params: params })

        reg("theme.toggle", (*) => DesktopModule.ToggleTheme(), "Toggle Windows light/dark theme (and wallpaper)")
        reg("wallpaper.set", (path, style := "Fill") => WallpaperFunctions.SetWallpaper(Paths.Expand(path), style),
            "Set the desktop wallpaper", "path, [style]")
        reg("wallpaper.bing", (*) => DesktopModule.SetBing(), "Set today's Bing image as wallpaper")

        reg("media.playPause", (*) => DesktopModule.Media("{Media_Play_Pause}", "⏯", "Play/Pause"), "Play/pause media")
        reg("media.next", (*) => DesktopModule.Media("{Media_Next}", "⏭", "Next"), "Next track")
        reg("media.previous", (*) => DesktopModule.Media("{Media_Prev}", "⏮", "Previous"), "Previous track")

        reg("keyboard.toggleCapsLock", (*) => DesktopModule.ToggleLock("CapsLock"), "Toggle Caps Lock (even when forced off)")
        reg("keyboard.toggleNumLock", (*) => DesktopModule.ToggleLock("NumLock"), "Toggle Num Lock (even when forced on)")

        reg("trayIcons.showAll", (*) => DesktopModule.ShowAllTrayIcons(), "Promote every tray icon to the visible area")
        reg("desktop.focus", (*) => DesktopModule.FocusDesktop(),
            "Focus the desktop without minimizing windows, so system shortcuts reach Windows")
        reg("taskbar.activate", (n) => DesktopModule.ActivateTaskbarItem(n),
            "Like Win+<n>: start, switch to, or cycle taskbar app n (1-10; 0 = 10), even under a full-screen app", "n")
        reg("powerToys.toggleAwake", (*) => DesktopModule.TogglePowerToysAwake(),
            "Toggle PowerToys Awake between indefinite and off")
    }

    static Start(cfg) {
        capsLock := cfg.Get("settings.keyboard.capsLock", "")
        if (capsLock != "")
            SetCapsLockState(capsLock)
        numLock := cfg.Get("settings.keyboard.numLock", "")
        if (numLock != "")
            SetNumLockState(numLock)
        if (cfg.ModuleEnabled("trayIcons")) {
            DesktopModule.ShowAllTrayIcons()
            SetTimer((*) => DesktopModule.ShowAllTrayIcons(), 1000 * cfg.Get("modules.trayIcons.intervalSeconds", 60))
        }
    }

    ; Toggles the theme, then applies the wallpaper configured for the new mode:
    ; "bing", a file path, or "" (leave unchanged).
    static ToggleTheme() {
        result := ThemeFunctions.ToggleTheme()
        mode := result.Get("current") = 1 ? "light" : "dark"
        target := MapGet(DesktopModule.Wallpaper, mode, "")
        if (target = "bing")
            DesktopModule.SetBing()
        else if (target != "")
            WallpaperFunctions.SetWallpaper(Paths.Expand(target))
        return result
    }

    static SetBing() {
        dir := Paths.Expand(MapGet(DesktopModule.Bing, "cacheDir", ""))
        return WallpaperFunctions.SetBingWallpaper(dir, MapGet(DesktopModule.Bing, "maxAgeDays", 5))
    }

    static Media(key, icon, label) {
        Send(key)
        Toast.ShowToast({ fadeDelay: 800 }, { text: icon, size: 24 }, { text: label, size: 14 })
    }

    static ToggleLock(name) {
        state := GetKeyState(name, "T") ? "AlwaysOff" : "AlwaysOn"
        if (name = "CapsLock")
            SetCapsLockState(state)
        else
            SetNumLockState(state)
    }

    ; Gives keyboard focus to the desktop without minimizing, hiding, or moving
    ; any window, so system-wide shortcuts (Win+<key>, Alt+Tab, ...) reach the
    ; shell even while a full-screen app is capturing them.
    static FocusDesktop() {
        hwnd := DesktopModule.PickDesktopHost(DesktopModule.DesktopCandidates())
        if (!hwnd) {
            Toast.ShowToast({ color: "Red", fadeDelay: 3000 }, "Focus Desktop:", "Desktop window not found")
            return 0
        }
        WinActivate(hwnd)
        ; Focus the icon view so keyboard input lands on the desktop itself.
        try ControlFocus("SysListView321", hwnd)
        return hwnd
    }

    ; Win+<n> for taskbar slot n. A full-screen window (remote desktop, VDI
    ; viewer, game) usually captures Win+<n> itself, so the desktop gets focus
    ; first and Windows receives the keystroke.
    ;
    ; Bound on a layer, Win stays down while the layer key (e.g. CapsLock) is
    ; held, as if Win itself were held: repeated presses step through an app's
    ; windows, and Windows switches to the selected one when the layer key is
    ; released. Outside a layer, or with Ctrl/Alt/Shift held, it is a single
    ; Win+<n> press. While Win is held, the triggering key repeats through a
    ; temporary wildcard hotkey (plain bindings don't match with Win down);
    ; other keys reach Windows as Win+<key>, as when Win itself is held.
    static _TaskbarHold := ""
    static _TaskbarReleaseRegistered := false
    static _TaskbarHoldContext := (*) => !!DesktopModule._TaskbarHold

    static ActivateTaskbarItem(n) {
        digit := DesktopModule.TaskbarDigit(n)
        ; Virtual key of the number-row key, so layouts that need Shift for
        ; digits (AZERTY) don't turn this into Win+Shift+<n> (new instance).
        key := "{vk3" digit "}"
        if (DesktopModule._TaskbarHold) {
            Send("{Blind^!+}" key)
            return
        }
        if (DesktopModule.ForegroundIsFullScreen()) {
            hwnd := DesktopModule.FocusDesktop()
            if (!hwnd)
                return
            ; If the app keeps focus, Win+<n> would go to it instead of Windows.
            if (!WinWaitActive(hwnd, , 0.5))
                return Toast.ShowToast({ color: "Red", fadeDelay: 3000 }, "Taskbar:", "Could not move focus off the full-screen window")
        }
        isDown := (k) => GetKeyState(k, "P")
        held := DesktopModule.TaskbarHoldKeys(
            DesktopModule.TaskbarTriggerKeys(Bindings.specs, Bindings.layers, A_ThisHotkey), isDown)
        ; Held modifiers would leak into a held Win (Win+Shift+<n> starts a new
        ; instance), so they get the plain press, which releases them for it.
        if (!held.Length || DesktopModule.TaskbarHoldKeys(["Ctrl", "Alt", "Shift"], isDown).Length) {
            Send("#" key)
            return
        }
        if (!DesktopModule._TaskbarReleaseRegistered) {
            OnExit((*) => DesktopModule.ReleaseTaskbarHold())
            DesktopModule._TaskbarReleaseRegistered := true
        }
        repeat := DesktopModule.TaskbarRepeatKey(A_ThisHotkey)
        DesktopModule._TaskbarHold := { keys: held, started: A_TickCount, repeat: repeat }
        Send("{Blind}{LWin down}" key)
        if (repeat != "") {
            HotIf(DesktopModule._TaskbarHoldContext)
            ; Win stays held; Ctrl/Alt/Shift are lifted for the key, as on the first press.
            Hotkey("*" repeat, (*) => Send("{Blind^!+}" key), "On")
            HotIf()
        }
        SetTimer(DesktopModule._TaskbarPoll, 30)
    }

    static _TaskbarPoll := (*) => DesktopModule.PollTaskbarHold()

    static PollTaskbarHold() {
        hold := DesktopModule._TaskbarHold
        if (!hold)
            return SetTimer(DesktopModule._TaskbarPoll, 0)
        if (A_TickCount - hold.started > 60000
            || !DesktopModule.TaskbarHoldKeys(hold.keys, (k) => GetKeyState(k, "P")).Length)
            DesktopModule.ReleaseTaskbarHold()
    }

    static ReleaseTaskbarHold() {
        SetTimer(DesktopModule._TaskbarPoll, 0)
        if (!DesktopModule._TaskbarHold)
            return
        repeat := DesktopModule._TaskbarHold.repeat
        DesktopModule._TaskbarHold := ""
        if (repeat != "") {
            HotIf(DesktopModule._TaskbarHoldContext)
            try Hotkey("*" repeat, "Off")
            HotIf()
        }
        Send("{Blind}{LWin up}")
    }

    ; Pure: the plain key of the hotkey that ran the action, for repeating it
    ; while Win is held; "" for combinations, release hotkeys, or none.
    static TaskbarRepeatKey(hotkey) {
        base := RegExReplace(hotkey, "^[~*$#!^+<>]+")
        if (base = "" || InStr(base, " "))
            return ""
        return base
    }

    ; Pure: the layer keys of the taskbar.activate bindings registered on
    ; hotkey; empty for bindings outside a layer.
    static TaskbarTriggerKeys(specs, layers, hotkey) {
        keys := []
        for spec in specs {
            if (spec.HasOwnProp("action") && spec.action = "taskbar.activate" && spec.keys = hotkey
                && spec.layer != "" && layers.Has(spec.layer))
                keys.Push(layers[spec.layer].key)
        }
        return keys
    }

    ; Pure: the candidate keys that isDown reports as held, without duplicates.
    static TaskbarHoldKeys(candidates, isDown) {
        out := [], seen := Map()
        seen.CaseSense := "Off"
        for k in candidates {
            if (k != "" && !seen.Has(k) && isDown(k)) {
                seen[k] := true
                out.Push(k)
            }
        }
        return out
    }

    ; Pure: the number-row digit for taskbar slot n (1-9, then 10 or 0 for "0").
    static TaskbarDigit(n) {
        if (IsInteger(n)) {
            n := Integer(n)
            if (n >= 1 && n <= 9)
                return String(n)
            if (n = 10 || n = 0)
                return "0"
        }
        throw ValueError("Taskbar slot must be 1-10 (0 means 10): " n)
    }

    static ForegroundIsFullScreen() {
        hwnd := WinExist("A")
        if (!hwnd)
            return false
        try {
            cls := WinGetClass(hwnd)
            style := WinGetStyle(hwnd)
        } catch
            return false
        win := Buffer(16, 0)
        if !DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", win)
            return false
        mon := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr") ; MONITOR_DEFAULTTONEAREST
        info := Buffer(40, 0)
        NumPut("UInt", 40, info)
        if (!mon || !DllCall("GetMonitorInfoW", "Ptr", mon, "Ptr", info))
            return false
        return DesktopModule.IsFullScreen(cls, style, DesktopModule.ReadRect(win, 0), DesktopModule.ReadRect(info, 4))
    }

    static ReadRect(buf, offset) {
        return { left: NumGet(buf, offset, "Int"), top: NumGet(buf, offset + 4, "Int"),
            right: NumGet(buf, offset + 8, "Int"), bottom: NumGet(buf, offset + 12, "Int") }
    }

    ; Pure: a captionless window covering its whole monitor, other than the
    ; shell's own desktop and taskbar windows. Maximized windows keep their
    ; caption, so they don't count even when the taskbar auto-hides.
    static IsFullScreen(cls, style, win, monitor) {
        for shell in ["Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd"] {
            if (cls = shell)
                return false
        }
        if ((style & 0xC00000) = 0xC00000) ; WS_CAPTION
            return false
        return win.left <= monitor.left && win.top <= monitor.top
            && win.right >= monitor.right && win.bottom >= monitor.bottom
    }

    ; Snapshot of the top-level windows that can host the desktop icons. The
    ; icon view (SHELLDLL_DefView) lives under Progman, or under a WorkerW once
    ; a wallpaper slideshow or animation has been started.
    static DesktopCandidates() {
        out := []
        for cls in ["Progman", "WorkerW"] {
            for hwnd in WinGetList("ahk_class " cls) {
                defView := DllCall("FindWindowExW", "Ptr", hwnd, "Ptr", 0, "Str", "SHELLDLL_DefView", "Ptr", 0, "Ptr")
                out.Push({ hwnd: hwnd, cls: cls, hasDefView: defView != 0 })
            }
        }
        return out
    }

    ; Pure: the window hosting the icon view wins; otherwise Progman; otherwise 0.
    static PickDesktopHost(candidates) {
        for c in candidates {
            if (c.hasDefView)
                return c.hwnd
        }
        for c in candidates {
            if (c.cls = "Progman")
                return c.hwnd
        }
        return 0
    }

    ; Windows 11 hides new tray icons; mark them all as promoted.
    static ShowAllTrayIcons() {
        loop reg "HKEY_CURRENT_USER\Control Panel\NotifyIconSettings", "KR" {
            try RegWrite(1, "REG_DWORD", A_LoopRegKey "\" A_LoopRegName, "IsPromoted")
        }
    }

    ; Flips PowerToys Awake between indefinite (1) and passive (0) by editing its
    ; settings file, which PowerToys watches. Re-read on every call so changes
    ; made in the PowerToys UI are respected.
    static TogglePowerToysAwake() {
        path := EnvGet("LocalAppData") "\Microsoft\PowerToys\Awake\settings.json"
        try {
            settings := JSON.Parse(FileRead(path, "UTF-8"))
            props := settings["properties"]
            next := DesktopModule.NextAwakeMode(props.Has("mode") ? props["mode"] : 0)
            props["mode"] := next
            f := FileOpen(path, "w", "UTF-8")
            if !f
                throw OSError("Unable to open Awake settings for writing")
            f.Write(JSON.Stringify(settings))
            f.Close()
        } catch as e {
            return Toast.ShowToast({ color: "Red", fadeDelay: 5000 }, "Failed to toggle:", "PowerToys Awake`n" e.Message)
        }
        Toast.ShowToast(, "Keep Awake:", next = 1 ? "On" : "Off")
    }

    static NextAwakeMode(current) => current = 1 ? 0 : 1
}
