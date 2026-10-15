#Requires AutoHotkey v2.0

; Resolves where user-owned files live. Everything personal (config, plugins,
; private libraries) sits in one directory outside the repository.
;
; Resolution order for the config directory:
;   1. Paths.Override (set from the --config-dir command-line flag)
;   2. %HOTKIT_CONFIG_DIR%
;   3. %XDG_CONFIG_HOME%\hotkit
;   4. %USERPROFILE%\.config\hotkit
class Paths {
    static AppName := "hotkit"
    static Override := ""

    static ConfigDir() {
        if (Paths.Override != "")
            return Paths.Normalize(Paths.Override)
        envDir := EnvGet("HOTKIT_CONFIG_DIR")
        if (envDir != "")
            return Paths.Normalize(envDir)
        xdg := EnvGet("XDG_CONFIG_HOME")
        if (xdg != "")
            return Paths.Normalize(xdg "\" Paths.AppName)
        return Paths.Normalize(EnvGet("USERPROFILE") "\.config\" Paths.AppName)
    }

    static ConfigFile() => Paths.ConfigDir() "\config.json"
    static PluginDir() => Paths.ConfigDir() "\plugins"

    ; Repository root (parent of src\).
    static RepoRoot() => Paths.Normalize(A_LineFile "\..\..\..")
    static ExampleConfig() => Paths.RepoRoot() "\config\config.example.json"
    ; Git-ignored directory for machine-local generated files.
    static LocalDir() => Paths.RepoRoot() "\local"
    static PluginStub() => Paths.LocalDir() "\plugins.generated.ahk"

    ; Expands %VAR% references and resolves "." / ".." segments.
    static Expand(path) {
        out := path
        pos := 1
        while (RegExMatch(out, "%([A-Za-z_][A-Za-z0-9_()]*)%", &m, pos)) {
            value := EnvGet(m[1])
            out := SubStr(out, 1, m.Pos - 1) value SubStr(out, m.Pos + m.Len)
            pos := m.Pos + StrLen(value)
        }
        if (SubStr(out, 1, 2) = "~\" || SubStr(out, 1, 2) = "~/" || out = "~")
            out := EnvGet("USERPROFILE") SubStr(out, 2)
        return out
    }

    static Normalize(path) {
        path := StrReplace(Paths.Expand(path), "/", "\")
        isUnc := SubStr(path, 1, 2) = "\\"
        parts := []
        for part in StrSplit(path, "\") {
            if (part = "" || part = ".")
                continue
            if (part = "..") {
                if (parts.Length && parts[parts.Length] != "..")
                    parts.Pop()
                else
                    parts.Push(part)
                continue
            }
            parts.Push(part)
        }
        out := ""
        for i, part in parts
            out .= (i = 1 ? "" : "\") part
        return (isUnc ? "\\" : "") out
    }
}
