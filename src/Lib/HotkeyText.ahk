#Requires AutoHotkey v2.0

; Pure helpers for AutoHotkey hotkey notation. No side effects; unit tested.
class HotkeyText {
    static ModifierNames := Map(
        "#", "Win", "^", "Ctrl", "!", "Alt", "+", "Shift")

    ; Splits a hotkey into its prefix flags, modifiers, and key part.
    ;   ">^>!<+PgUp" -> {mods: [RCtrl, RAlt, LShift], key: "PgUp", up: false}
    ;   "LShift & Volume_Up" -> {mods: [LShift], key: "Volume_Up", up: false}
    ; Keys are returned exactly as written; use KeyName() for display.
    static Parse(hk) {
        result := { mods: [], key: "", up: false, wildcard: false, passThrough: false }
        work := Trim(hk)
        if (RegExMatch(work, "i)\s+up$")) {
            result.up := true
            work := RegExReplace(work, "i)\s+up$")
        }
        if (InStr(work, " & ")) {
            parts := StrSplit(work, "&", " `t")
            result.mods.Push(Trim(parts[1]))
            result.key := Trim(parts[2])
            return result
        }
        side := ""
        i := 1
        while (i <= StrLen(work)) {
            ch := SubStr(work, i, 1)
            ; A single remaining character is the key itself (e.g. "^!+" or "#=").
            if (i = StrLen(work))
                break
            if (ch = "<" || ch = ">") {
                side := ch = "<" ? "L" : "R"
            } else if (HotkeyText.ModifierNames.Has(ch)) {
                result.mods.Push(side HotkeyText.ModifierNames[ch])
                side := ""
            } else if (ch = "*") {
                result.wildcard := true
            } else if (ch = "~") {
                result.passThrough := true
            } else if (ch = "$") {
                ; Hook prefix; no display impact.
            } else {
                break
            }
            i++
        }
        result.key := Trim(SubStr(work, i))
        return result
    }

    ; The physical key that ends the hotkey (used for KeyWait / release tracking).
    static BaseKey(hk) => HotkeyText.Parse(hk).key

    ; Human-readable form: ">^>!PgUp" -> "RCtrl+RAlt+PgUp".
    static Format(hk, layerLabel := "") {
        p := HotkeyText.Parse(hk)
        parts := []
        if (layerLabel != "")
            parts.Push(layerLabel)
        for m in p.mods
            parts.Push(HotkeyText.KeyName(m))
        parts.Push(HotkeyText.KeyName(p.key))
        out := ""
        for i, part in parts
            out .= (i = 1 ? "" : "+") part
        return out (p.up ? " (release)" : "")
    }

    static KeyName(key) {
        key := Trim(key)
        static aliases := Map("Volume_Mute", "Mute",
            "Volume_Up", "Volume Up", "Volume_Down", "Volume Down")
        if (aliases.Has(key))
            return aliases[key]
        if (StrLen(key) = 1)
            return StrUpper(key)
        return key
    }

    ; Converts hotkey notation into a SendEvent sequence:
    ;   ">+F24" -> "{RShift down}{F24}{RShift up}"
    static ToSendEvent(hk) {
        p := HotkeyText.Parse(hk)
        downs := ""
        ups := ""
        for m in p.mods {
            name := RegExMatch(m, "^[LR]") ? m : "L" m
            downs .= "{" name " down}"
            ups := "{" name " up}" ups
        }
        return downs (p.key != "" ? "{" p.key "}" : "") ups
    }
}
