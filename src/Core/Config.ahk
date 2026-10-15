#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\..\Lib\JSON.ahk

; JSON configuration with comments and trailing commas allowed (JSONC).
;
; Values are normalized on load so callers never see JSON sentinels:
;   true -> 1, false -> 0, null -> "" ; objects -> Map ; arrays -> Array
;
; Usage:
;   cfg := Config.FromFile(path)
;   cfg.Get("modules.displayScale.presets", [100, 125])
;   cfg.Section("apps")            ; Map, empty when missing
class Config {
    __New(data := unset, path := "") {
        this.data := IsSet(data) ? data : Map()
        this.path := path
    }

    static FromFile(path) {
        text := FileRead(path, "UTF-8")
        try {
            data := Config.Parse(text)
        } catch as e {
            throw ValueError("Invalid JSON in " path ": " e.Message)
        }
        return Config(data, path)
    }

    static FromText(text) => Config(Config.Parse(text))

    static Parse(text) {
        raw := JSON.Parse(text, { allowComments: true, allowTrailingCommas: true })
        if !(raw is Map)
            throw ValueError("Top-level JSON value must be an object.")
        return Config.Normalize(raw)
    }

    ; Converts JSON sentinels into native AHK values, recursively.
    static Normalize(value) {
        if (IsObject(value)) {
            if (value = JSON.True)
                return true
            if (value = JSON.False)
                return false
            if (value = JSON.Null)
                return ""
            if (value is Map) {
                out := Map()
                out.CaseSense := "Off"
                for k, v in value
                    out[k] := Config.Normalize(v)
                return out
            }
            if (value is Array) {
                out := []
                for v in value
                    out.Push(Config.Normalize(v))
                return out
            }
        }
        return value
    }

    ; Dotted-path lookup. Returns default when any segment is missing.
    Get(path, default := "") {
        node := this.data
        for key in StrSplit(path, ".") {
            if !(node is Map) || !node.Has(key)
                return default
            node := node[key]
        }
        return node
    }

    Has(path) {
        sentinel := {}
        return this.Get(path, sentinel) != sentinel
    }

    Section(path) {
        value := this.Get(path, "")
        return (value is Map) ? value : Map()
    }

    List(path) {
        value := this.Get(path, "")
        return (value is Array) ? value : []
    }

    ; True when a module section exists and is not disabled with "enabled": false.
    ModuleEnabled(name, defaultEnabled := false) {
        section := this.Get("modules." name, "")
        if (section is Map)
            return section.Has("enabled") ? !!section["enabled"] : true
        if (section = "")
            return defaultEnabled
        return !!section
    }
}

; Reads an option from a Map with a default; tolerates non-Map inputs.
MapGet(source, key, default := "") {
    return (source is Map && source.Has(key)) ? source[key] : default
}
