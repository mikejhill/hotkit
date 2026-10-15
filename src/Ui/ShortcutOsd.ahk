#Requires AutoHotkey v2.0

; Searchable overlay listing every bound shortcut, generated from the live
; binding table (so it is always accurate). Open from the tray menu or bind
; the "osd.toggle" action to a key.
;
; Type to filter; Esc or the bound key closes it.
class ShortcutOsd {
    static Gui := ""
    static Title := "Keyboard Shortcuts"
    static ConfigPath := ""
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
        ShortcutOsd._rows := Bindings.Rows()
        if !IsObject(ShortcutOsd.Gui)
            ShortcutOsd._Build()
        ShortcutOsd.Gui["Filter"].Value := ""
        ShortcutOsd.Fill("")
        ShortcutOsd._SetStatus()
        ShortcutOsd.Gui.Show("w900 h560 Center")
        ShortcutOsd.Gui["Filter"].Focus()
    }

    static Close() {
        if IsObject(ShortcutOsd.Gui)
            ShortcutOsd.Gui.Hide()
    }

    ; mutate: on
    ; Pure: rows whose text contains every whitespace-separated term.
    static FilterRows(rows, query) {
        terms := StrSplit(Trim(query), " ", "`t")
        out := []
        for row in rows {
            hay := row.keys " " row.description " " row.action " " row.layer " " row.group " " row.source
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
        for row in ShortcutOsd.FilterRows(ShortcutOsd._rows, query) {
            scope := row.group != "" ? row.group (row.active ? "" : " (off)") : ""
            lv.Add(, row.keys, row.description, scope, row.action, row.source)
        }
        loop 5
            lv.ModifyCol(A_Index, "AutoHdr")
        lv.Opt("+Redraw")
    }

    static _Build() {
        g := Gui("+Resize +MinSize600x300 +AlwaysOnTop", ShortcutOsd.Title)
        g.SetFont("s10", "Segoe UI")
        g.MarginX := 12
        g.MarginY := 12
        g.Add("Edit", "vFilter w876", "")
        SendMessage(0x1501, true, StrPtr("Filter shortcuts…"), g["Filter"])  ; EM_SETCUEBANNER
        g["Filter"].OnEvent("Change", (ctl, *) => ShortcutOsd.Fill(ctl.Value))
        g.Add("ListView", "vList w876 h470 -Multi Grid", ["Shortcut", "Description", "Group", "Action", "Source"])
        g.Add("Text", "vStatus w876", "")
        g.OnEvent("Escape", (*) => ShortcutOsd.Close())
        g.OnEvent("Close", (*) => ShortcutOsd.Close())
        g.OnEvent("Size", (gg, mm, w, h) => ShortcutOsd._OnSize(gg, mm, w, h))
        ShortcutOsd.Gui := g
    }

    static _OnSize(g, minMax, w, h) {
        if (minMax = -1)
            return
        g["Filter"].Move(, , w - 24)
        g["List"].Move(, , w - 24, h - 100)
        g["Status"].Move(, h - 30, w - 24)
    }

    static _SetStatus() {
        problems := Bindings.problems.Length
        text := ShortcutOsd._rows.Length " shortcuts · config: " ShortcutOsd.ConfigPath
        if (problems)
            text .= " · " problems " problem(s): see tray › Show Config Problems"
        ShortcutOsd.Gui["Status"].Value := text
    }
}
