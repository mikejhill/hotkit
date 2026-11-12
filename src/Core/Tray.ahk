#Requires AutoHotkey v2.0

; Builds the tray menu: shortcut overlay, user-defined items, module menus,
; and config shortcuts. User items come from config:
;
;   "tray": {
;     "items": [
;       { "label": "Toggle &Theme", "action": "theme.toggle" },
;       { "label": "Tools", "items": [ { "label": "Notes", "action": "app.toggle", "args": ["notes"] } ] },
;       { "separator": true }
;     ]
;   }
;
; When "layers" are defined, a Layer submenu lists them with the active one
; checked; picking one switches to it.
class Tray {
    static LayerMenu := ""
    static _layerItems := Map()

    static Build(cfg, moduleMenus) {
        root := A_TrayMenu
        root.Delete()
        root.Add("Show &Shortcuts", ActionRegistry.Callback("osd.toggle"))
        root.Default := "Show &Shortcuts"
        Tray.LayerMenu := ""
        Tray._layerItems := Map()
        if (Bindings.layerOrder.Length) {
            Tray.LayerMenu := Menu()
            for i, name in Bindings.layerOrder {
                item := Tray.LayerItemText(i, Bindings.layers[name])
                Tray._layerItems[name] := item
                Tray.LayerMenu.Add(item, Tray._LayerCallback(name), "Radio")
            }
            root.Add("&Layer", Tray.LayerMenu)
            Tray.UpdateLayers()
        }

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

    ; Pure: menu text for the i-th layer; the first ten get 1-9, 0 as access keys.
    static LayerItemText(i, layer) {
        text := StrReplace(layer.label, "&", "&&")
        if (layer.description != "")
            text .= "`t" StrReplace(layer.description, "&", "&&")
        return i <= 10 ? "&" Mod(i, 10) " " text : text
    }

    static _LayerCallback(name) => ActionRegistry.Callback(Map("action", "layer.activate", "args", [name]))

    ; Checks the active layer in the Layer submenu.
    static UpdateLayers() {
        if !IsObject(Tray.LayerMenu)
            return
        for name, item in Tray._layerItems {
            if (name = Bindings.activeLayer)
                Tray.LayerMenu.Check(item)
            else
                Tray.LayerMenu.Uncheck(item)
        }
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
