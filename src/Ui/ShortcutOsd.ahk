#Requires AutoHotkey v2.0

; Searchable overlay listing every bound shortcut, generated from the live
; binding table (so it is always accurate). Open from the tray menu or bind
; the "osd.toggle" action to a key.
;
; Type to filter; Esc or the bound key closes it. With layers defined, it lists
; the active layer's shortcuts (plus those on every layer); "All layers" shows
; the rest too.
class ShortcutOsd {
    static Gui := ""
    static Title := "Keyboard Shortcuts"
    static ConfigPath := ""
    static AllLayers := false
    static _rows := []

    ; mutate: off (GUI; covered by e2e)
    static Toggle() {
        if (ShortcutOsd.IsOpen())
            return ShortcutOsd.Close()
        ShortcutOsd.Show()
    }

    static IsOpen() {
        if !IsObject(ShortcutOsd.Gui)
            return false
        try return DllCall("IsWindowVisible", "ptr", ShortcutOsd.Gui.Hwnd)
        return false
    }

    static Show() {
        if !IsObject(ShortcutOsd.Gui)
            ShortcutOsd._Build()
        ShortcutOsd.Gui["Filter"].Value := ""
        ShortcutOsd.Refresh()
        ShortcutOsd.Gui.Show("w900 h560 Center")
        ShortcutOsd.Gui["Filter"].Focus()
    }

    ; Re-reads the binding table (e.g. after the active layer changed).
    static Refresh() {
        if !IsObject(ShortcutOsd.Gui)
            return
        ShortcutOsd._rows := Bindings.Rows()
        hasLayers := Bindings.layerOrder.Length > 0
        ShortcutOsd.Gui["AllLayers"].Visible := hasLayers
        ShortcutOsd.Gui["AllLayers"].Value := ShortcutOsd.AllLayers
        ShortcutOsd.Fill(ShortcutOsd.Gui["Filter"].Value)
        ShortcutOsd._SetStatus()
    }

    static Close() {
        if IsObject(ShortcutOsd.Gui)
            ShortcutOsd.Gui.Hide()
    }

    ; mutate: on
    ; Pure: rows whose text contains every whitespace-separated term; rows on
    ; inactive layers only when allLayers is set.
    static FilterRows(rows, query, allLayers := true) {
        terms := StrSplit(Trim(query), " ", "`t")
        out := []
        for row in rows {
            if (!allLayers && !row.onLayer)
                continue
            hay := row.keys " " row.description " " row.action " " row.modifier " " row.layers " " row.group " " row.source
            keep := true
            for term in terms {
                if (term != "" && !InStr(hay, term)) {
                    keep := false
                    break
                }
            }
            if keep
                out.Push(row)
        }
        return out
    }

    ; mutate: off (GUI; covered by e2e)
    static Fill(query) {
        lv := ShortcutOsd.Gui["List"]
        lv.Opt("-Redraw")
        lv.Delete()
        for row in ShortcutOsd.FilterRows(ShortcutOsd._rows, query, ShortcutOsd.AllLayers) {
            layerText := row.overridden ? "(overridden on " Bindings.layers[Bindings.activeLayer].label ")"
                : row.layers = "" ? "" : row.layers (row.onLayer ? "" : " (inactive)")
            scope := row.group != "" ? row.group (Bindings.GroupEnabled(row.group) ? "" : " (off)") : ""
            lv.Add(, row.keys, row.description, layerText, scope, row.action, row.source)
        }
        loop 6
            lv.ModifyCol(A_Index, "AutoHdr")
        lv.Opt("+Redraw")
    }

    static _Build() {
        g := Gui("+Resize +MinSize600x300 +AlwaysOnTop", ShortcutOsd.Title)
        g.SetFont("s10", "Segoe UI")
        g.MarginX := 12
        g.MarginY := 12
        g.Add("Edit", "vFilter w760", "")
        SendMessage(0x1501, true, StrPtr("Filter shortcuts…"), g["Filter"])  ; EM_SETCUEBANNER
        g["Filter"].OnEvent("Change", (ctl, *) => ShortcutOsd.Fill(ctl.Value))
        g.Add("CheckBox", "vAllLayers x+12 yp+3 w104", "All layers")
        g["AllLayers"].OnEvent("Click", (ctl, *) => (ShortcutOsd.AllLayers := ctl.Value, ShortcutOsd.Fill(g["Filter"].Value)))
        g.Add("ListView", "vList xm w876 h470 -Multi Grid", ["Shortcut", "Description", "Layer", "Group", "Action", "Source"])
        g.Add("Text", "vStatus w876", "")
        g.OnEvent("Escape", (*) => ShortcutOsd.Close())
        g.OnEvent("Close", (*) => ShortcutOsd.Close())
        g.OnEvent("Size", (gg, mm, w, h) => ShortcutOsd._OnSize(gg, mm, w, h))
        ShortcutOsd.Gui := g
    }

    static _OnSize(g, minMax, w, h) {
        if (minMax = -1)
            return
        g["Filter"].Move(, , w - 140)
        g["AllLayers"].Move(w - 116)
        g["List"].Move(, , w - 24, h - 100)
        g["Status"].Move(, h - 30, w - 24)
    }

    static _SetStatus() {
        problems := Bindings.problems.Length
        text := ""
        if (Bindings.activeLayer != "")
            text .= Bindings.layers[Bindings.activeLayer].label " active · "
        text .= ShortcutOsd._rows.Length " shortcuts · config: " ShortcutOsd.ConfigPath
        if (problems)
            text .= " · " problems " problem(s): see tray › Show Config Problems"
        ShortcutOsd.Gui["Status"].Value := text
    }
}
