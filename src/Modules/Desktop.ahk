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
        if (!hwnd)
            return Toast.ShowToast({ color: "Red", fadeDelay: 3000 }, "Focus Desktop:", "Desktop window not found")
        WinActivate(hwnd)
        ; Focus the icon view so keyboard input lands on the desktop itself.
        try ControlFocus("SysListView321", hwnd)
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
