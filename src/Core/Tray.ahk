#Requires AutoHotkey v2.0

; Sets the tray icon and builds the tray menu: shortcut overlay, user-defined
; items, module menus, and config shortcuts. Both come from config:
;
;   "tray": {
;     "icon": "icons\my.ico",                          ; or { "file": "shell32.dll", "index": 44 }
;     "items": [
;       { "label": "Toggle &Theme", "action": "theme.toggle" },
;       { "label": "Tools", "items": [ { "label": "Notes", "action": "app.toggle", "args": ["notes"] } ] },
;       { "separator": true }
;     ]
;   }
class Tray {
    static Version := ""
    static _status := []

    ; Adds a status to the tray tooltip: fn returns a short text, or "" for
    ; none. Call Tray.RefreshTip() when it changes.
    static AddStatus(fn) => Tray._status.Push(fn)

    static RefreshTip() {
        parts := []
        for fn in Tray._status {
            try {
                s := fn.Call()
                if (s != "")
                    parts.Push(s)
            }
        }
        A_IconTip := Tray.Tip(Tray.Version, parts)
    }

    ; Pure: "hotkit 1.2.0", or "hotkit 1.2.0: a, b" with statuses.
    static Tip(version, parts) {
        tip := "hotkit " version
        for s in parts
            tip .= (A_Index = 1 ? ": " : ", ") s
        return tip
    }

    static DefaultIcon() => Paths.RepoRoot() "\assets\hotkit.ico"

    ; Reads tray.icon. Returns { file, index, custom, problem }: the icon to use,
    ; and a problem message when the configured icon can't be used (the default
    ; icon is returned in its place). %VAR% and ~ are expanded; see
    ; FindIconFile for relative paths.
    static ResolveIcon(cfg) {
        fallback := (problem) => ({ file: Tray.DefaultIcon(), index: 1, custom: false, problem: problem })
        spec := cfg.Get("tray.icon", "")
        index := 1
        if (spec is Map) {
            iconFile := MapGet(spec, "file", "")
            index := MapGet(spec, "index", 1)
        } else {
            iconFile := spec
        }
        if (IsObject(iconFile) || iconFile = "")
            return fallback(spec is Map ? "tray.icon: missing 'file'; using the default icon." : "")
        if (!IsInteger(index) || index = 0)
            return fallback("tray.icon: 'index' must be a non-zero whole number; using the default icon.")
        path := Tray.FindIconFile(Paths.Expand(iconFile), cfg.path != "" ? cfg.path : Paths.ConfigFile())
        if (path = "")
            return fallback("tray.icon: file not found: " iconFile "; using the default icon.")
        return { file: path, index: Integer(index), custom: true, problem: "" }
    }

    ; Absolute paths are used as given. A relative path is looked up next to the
    ; config file, then (a bare file name such as shell32.dll) in System32.
    static FindIconFile(path, configFile) {
        candidates := []
        if (RegExMatch(path, "^([A-Za-z]:[\\/]|[\\/]{2})")) {
            candidates.Push(path)
        } else {
            candidates.Push(configFile "\..\" path)
            if (!RegExMatch(path, "[\\/]"))
                candidates.Push(A_WinDir "\System32\" path)
        }
        for c in candidates {
            c := Paths.Normalize(c)
            attr := FileExist(c)
            if (attr != "" && !InStr(attr, "D"))
                return c
        }
        return ""
    }

    ; Applies tray.icon (or the default icon). A configured icon that fails to
    ; load falls back to the default and is reported as a config problem.
    static ApplyIcon(cfg) {
        icon := Tray.ResolveIcon(cfg)
        if (icon.custom) {
            try {
                TraySetIcon(icon.file, icon.index)
                return icon
            } catch as e {
                Bindings.problems.Push("tray.icon: could not load icon " icon.index " from " icon.file
                    " (" e.Message "); using the default icon.")
            }
        }
        if (FileExist(Tray.DefaultIcon()))
            try TraySetIcon(Tray.DefaultIcon(), 1)
        return icon
    }

    static Build(cfg, moduleMenus) {
        Tray.ApplyIcon(cfg)
        root := A_TrayMenu
        root.Delete()
        root.Add("Show &Shortcuts", ActionRegistry.Callback("osd.toggle"))
        root.Default := "Show &Shortcuts"

        actions := Menu()
        count := Tray.AddItems(actions, cfg.List("tray.items"))
        for m in moduleMenus {
            if (count && A_Index = 1)
                actions.Add()
            actions.Add(m.label, m.menu)
            count++
        }
        if (count)
            root.Add("&Actions", actions)
        root.Add()
        root.Add("Open &Config Folder", ActionRegistry.Callback("app.openConfigFolder"))
        root.Add("&Edit Config", ActionRegistry.Callback("app.editConfig"))
        if (Bindings.problems.Length)
            root.Add("Show Config &Problems (" Bindings.problems.Length ")", ActionRegistry.Callback("app.showProblems"))
        root.Add()
        root.AddStandard()
        for name in ["&Edit Script", "&Window Spy"]
            try root.Delete(name)
    }

    ; Adds config items to a menu; returns how many were added.
    static AddItems(target, items) {
        added := 0
        for item in items {
            if !(item is Map)
                continue
            if (MapGet(item, "separator", false)) {
                target.Add()
                continue
            }
            label := MapGet(item, "label", "")
            if (label = "")
                continue
            if (item.Has("items")) {
                sub := Menu()
                Tray.AddItems(sub, item["items"])
                target.Add(label, sub)
            } else {
                try {
                    target.Add(label, ActionRegistry.Callback(item))
                } catch as e {
                    Bindings.problems.Push("tray item '" label "': " e.Message)
                    continue
                }
            }
            added++
        }
        return added
    }
}
