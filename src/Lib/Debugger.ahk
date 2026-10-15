#Requires AutoHotkey v2.0

class Debugger {
    static Enabled := false

    ; Logs the given message
    static Log(message, level := "INFO") {
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        logMessage := timestamp ": [" level "] " message "`n"
        OutputDebug(logMessage)
        if (Debugger.Enabled) {
            try {
                FileAppend(logMessage, A_ScriptName . ".log")
            } catch as e {
                ; Swallow
            }
        }
    }

    ; Returns a string with details about the specified hwnd.
    static DebugWinGetDetails(hwnd) {
        return "Hwnd: [" . hwnd . "]."
            . " Title: [" . WinGetTitle(hwnd) . "]."
            . " Class: [" . WinGetClass(hwnd) . "]."
            . " Exe: [" . WinGetProcessName(hwnd) . "]."
    }
}
