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
                Tray._icon := { file: icon.file, index: icon.index }
                Tray._ShowBadge()
                return icon
            } catch as e {
                Bindings.problems.Push("tray.icon: could not load icon " icon.index " from " icon.file
                    " (" e.Message "); using the default icon.")
            }
        }
        if (FileExist(Tray.DefaultIcon())) {
            try TraySetIcon(Tray.DefaultIcon(), 1)
            Tray._icon := { file: Tray.DefaultIcon(), index: 1 }
            Tray._ShowBadge()
        }
        return icon
    }

    ; ---------------- Warning badge                 ------------------------------

    ; While Badged is true the tray icon carries an amber "!" badge in its
    ; lower-right corner (used while a stay-awake toggle is on). The badge is
    ; drawn onto whichever icon is in use, including a custom tray.icon.
    static Badged := false
    static _icon := ""

    static SetBadge(on) {
        on := !!on
        if (on = Tray.Badged)
            return
        Tray.Badged := on
        if (Tray._icon = "")
            return
        if (on)
            Tray._ShowBadge()
        else
            try TraySetIcon(Tray._icon.file, Tray._icon.index)
    }

    static _ShowBadge() {
        if (!Tray.Badged || Tray._icon = "")
            return
        size := DllCall("GetSystemMetrics", "Int", 49, "Int") ; SM_CXSMICON
        h := Tray.BadgedIcon(Tray._icon.file, Tray._icon.index, size)
        if (!h)
            return
        try TraySetIcon("HICON:*" h) ; "*": the tray keeps its own copy
        DllCall("DestroyIcon", "Ptr", h)
    }

    ; Pure: what a badge pixel is at (x, y) in a size x size icon: "ring"
    ; (dark outline), "mark" (dark "!"), "fill" (amber), or "" (the icon shows
    ; through). The badge is a circle in the lower-right corner.
    static BadgePixel(x, y, size) {
        r := size * 0.3
        cx := size - r, cy := size - r
        dx := x + 0.5 - cx, dy := y + 0.5 - cy
        d := Sqrt(dx * dx + dy * dy)
        if (d > r)
            return ""
        if (d > r - Max(1, size / 20))
            return "ring"
        half := Max(0.5, size / 32)
        if (Abs(dx) <= half) {
            if (dy >= -r * 0.62 && dy <= r * 0.12)
                return "mark"
            if (dy >= r * 0.3 && dy <= r * 0.3 + 2 * half)
                return "mark"
        }
        return "fill"
    }

    ; Returns a new HICON (caller destroys it): icon number index from file at
    ; size pixels with the warning badge drawn on, or 0 on failure.
    static BadgedIcon(file, index, size) {
        hSrc := 0, hdc := 0, hbm := 0, hMask := 0, old := 0
        try {
            hSrc := LoadPicture(file, "Icon" index " w" size " h" size, &imageType)
            if (!hSrc || imageType != 1)
                return 0
            bi := Buffer(40, 0)
            NumPut("UInt", 40, "Int", size, "Int", -size, "UShort", 1, "UShort", 32, bi)
            hdc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
            hbm := DllCall("CreateDIBSection", "Ptr", hdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
            if (!hbm || !bits)
                return 0
            old := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbm, "Ptr")
            DllCall("DrawIconEx", "Ptr", hdc, "Int", 0, "Int", 0, "Ptr", hSrc, "Int", size, "Int", size,
                "UInt", 0, "Ptr", 0, "UInt", 3) ; DI_NORMAL
            DllCall("GdiFlush")
            Tray._PaintBadge(bits, size)
            DllCall("SelectObject", "Ptr", hdc, "Ptr", old), old := 0
            hMask := DllCall("CreateBitmap", "Int", size, "Int", size, "UInt", 1, "UInt", 1, "Ptr", 0, "Ptr")
            info := Buffer(8 + 3 * A_PtrSize, 0) ; ICONINFO
            NumPut("Int", 1, info, 0)
            NumPut("Ptr", hMask, info, 8 + A_PtrSize)
            NumPut("Ptr", hbm, info, 8 + 2 * A_PtrSize)
            return DllCall("CreateIconIndirect", "Ptr", info, "Ptr")
        } finally {
            if (old)
                DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
            for obj in [hbm, hMask]
                if (obj)
                    DllCall("DeleteObject", "Ptr", obj)
            if (hdc)
                DllCall("DeleteDC", "Ptr", hdc)
            if (hSrc)
                DllCall("DestroyIcon", "Ptr", hSrc)
        }
    }

    ; Converts the drawn icon to straight alpha and paints the badge (BGRA).
    static _PaintBadge(bits, size) {
        anyAlpha := false
        loop size * size {
            if (NumGet(bits, (A_Index - 1) * 4 + 3, "UChar")) {
                anyAlpha := true
                break
            }
        }
        colors := Map("fill", 0xFFFFB000, "ring", 0xFF3A2A00, "mark", 0xFF3A2A00)
        loop size {
            y := A_Index - 1
            loop size {
                x := A_Index - 1
                off := (y * size + x) * 4
                kind := Tray.BadgePixel(x, y, size)
                if (kind != "") {
                    NumPut("UInt", colors[kind], bits, off)
                    continue
                }
                px := NumGet(bits, off, "UInt")
                a := anyAlpha ? px >> 24 : 255
                if (a > 0 && a < 255) {
                    ; DrawIconEx blends onto transparent black (premultiplied).
                    b := Min(255, Round((px & 0xFF) * 255 / a))
                    g := Min(255, Round(((px >> 8) & 0xFF) * 255 / a))
                    rr := Min(255, Round(((px >> 16) & 0xFF) * 255 / a))
                    px := (a << 24) | (rr << 16) | (g << 8) | b
                } else if (!anyAlpha) {
                    px := px | 0xFF000000
                }
                NumPut("UInt", px, bits, off)
            }
        }
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
        ; Reload like app.reload, so arguments and module state (BeforeRestart) carry over.
        try root.Add("&Reload Script", ActionRegistry.Callback("app.reload"))
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
