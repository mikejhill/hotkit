#Requires AutoHotkey v2.0

; Plain-text record of what the running app did: each start, config problems,
; load failures, skipped reloads and unhandled errors. Lives next to the config
; (<config dir>\hotkit.log) so tools and editors can see errors that otherwise
; only appear as a dialog or toast. tools/check.py prints the latest run.
;
; Each line: "yyyy-MM-dd HH:mm:ss [LEVEL] message". A run starts at a "started"
; INFO line. The file is trimmed to its newest lines once it grows too large.
class StatusLog {
    static MaxBytes := 65536
    static KeepLines := 300
    static Path := ""

    static File() => StatusLog.Path != "" ? StatusLog.Path : Paths.ConfigDir() "\hotkit.log"

    static Start(configPath) {
        StatusLog.Trim()
        StatusLog.Write("INFO", "started pid=" ProcessExist() " config=" configPath)
    }

    static Info(message) => StatusLog.Write("INFO", message)
    static Warn(message) => StatusLog.Write("WARN", message)
    static Error(message) => StatusLog.Write("ERROR", message)

    static Write(level, message) {
        line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" level "] " StrReplace(StrReplace(message, "`r"), "`n", " | ") "`n"
        try FileAppend(line, StatusLog.File(), "UTF-8")
    }

    ; Keeps the newest KeepLines lines once the file exceeds MaxBytes.
    static Trim() {
        path := StatusLog.File()
        try {
            if (!FileExist(path) || FileGetSize(path) <= StatusLog.MaxBytes)
                return
            lines := StrSplit(RTrim(FileRead(path, "UTF-8"), "`n"), "`n")
            out := ""
            first := Max(1, lines.Length - StatusLog.KeepLines + 1)
            loop lines.Length - first + 1
                out .= lines[first + A_Index - 1] "`n"
            f := FileOpen(path, "w", "UTF-8")
            f.Write(out)
            f.Close()
        }
    }

    ; OnError callback for run mode: records the error, then lets AutoHotkey
    ; show its usual dialog.
    static OnError(err, mode) {
        StatusLog.Error("unhandled (" mode "): " err.Message " (" err.File ":" err.Line ")")
        return 0
    }
}
