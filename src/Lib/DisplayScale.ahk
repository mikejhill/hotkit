#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\Toast.ahk

; Per-monitor display scaling (DPI) via SetDPI.exe:
;   https://github.com/imniko/SetDPI
;
;   DisplayScale.SetDpiPath := "C:\Tools\SetDpi.exe"
;   DisplayScale.Increase()          ; all monitors, one preset step
;   DisplayScale.Apply(150, 2)       ; monitor 2 -> 150%
;
; Repeated Increase/Decrease calls within DebounceMs are batched into one change.
class DisplayScale {
    static SetDpiPath := ""
    static Presets := [100, 125, 150, 175, 200, 225, 250, 300]
    static DebounceMs := 500
    static _pending := Map()
    static _timers := Map()

    ; ---------------- Pure helpers                  ------------------------------

    static ParseScale(text) => RegExMatch(text, "(\d{2,3})", &m) ? Integer(m[1]) : ""

    ; Moves `steps` presets from `current`, clamped to the preset range.
    static StepBy(current, steps, presets := "") {
        sorted := DisplayScale.SortNumeric(presets = "" ? DisplayScale.Presets : presets)
        if (steps = 0)
            return current
        startIdx := 0
        for idx, val in sorted {
            if (current >= val)
                startIdx := idx
            else
                break
        }
        return sorted[Max(1, Min(sorted.Length, startIdx + steps))]
    }

    static SortNumeric(arr) {
        sorted := arr.Clone()
        loop sorted.Length {
            i := A_Index
            j := i + 1
            while (j <= sorted.Length) {
                if (sorted[j] < sorted[i]) {
                    tmp := sorted[i]
                    sorted[i] := sorted[j]
                    sorted[j] := tmp
                }
                j++
            }
        }
        return sorted
    }

    static ValidateScale(scale) {
        if !IsInteger(scale)
            throw ValueError("Scale must be an integer value.")
        if (scale < 50 || scale > 400)
            throw ValueError("Scale should be between 50 and 400.")
        return Integer(scale)
    }

    ; ---------------- Commands                      ------------------------------

    ; mutate: off (runs SetDPI and reads monitors)
    static Get(monitor) {
        result := DisplayScale._Run(true, "value", monitor)
        scale := DisplayScale.ParseScale(result.stdout)
        if (scale = "")
            throw Error("Unable to read scale from SetDPI output.`n`n" result.stdout)
        return scale
    }

    static Set(scale, monitor) {
        DisplayScale._Run(false, DisplayScale.ValidateScale(scale), monitor)
    }

    ; Applies a preset to one monitor, or every monitor when monitor is "".
    static Apply(scale, monitor := "") {
        if (monitor = "") {
            loop MonitorGetCount()
                DisplayScale.Set(scale, A_Index)
            DisplayScale._Show(Format("Display Scaling: {1}% (all monitors)", scale))
        } else {
            DisplayScale.Set(scale, DisplayScale._ValidateMonitor(monitor))
            DisplayScale._Show(Format("Display Scaling: {1}% (monitor {2})", scale, monitor))
        }
    }

    static Increase(monitor := "") => DisplayScale.Adjust(1, monitor)
    static Decrease(monitor := "") => DisplayScale.Adjust(-1, monitor)

    static Adjust(direction, monitor := "") {
        if !(direction = 1 || direction = -1)
            throw ValueError("Direction must be 1 or -1.")
        monitors := []
        if (monitor = "") {
            loop MonitorGetCount()
                monitors.Push(A_Index)
        } else {
            monitors.Push(DisplayScale._ValidateMonitor(monitor))
        }
        for m in monitors
            DisplayScale._pending[m] := (DisplayScale._pending.Has(m) ? DisplayScale._pending[m] : 0) + direction
        key := monitor = "" ? "all" : monitor
        if DisplayScale._timers.Has(key)
            try SetTimer(DisplayScale._timers[key], 0)
        timer := () => DisplayScale._Flush(key, monitors)
        DisplayScale._timers[key] := timer
        SetTimer(timer, -DisplayScale.DebounceMs)
    }

    static ShowCurrent(monitor := "") {
        message := "Current Display Scaling:"
        if (monitor = "") {
            loop MonitorGetCount()
                message .= Format("`nMonitor {1}: {2}%", A_Index, DisplayScale.Get(A_Index))
        } else {
            message .= Format(" {1}% (monitor {2})", DisplayScale.Get(monitor), monitor)
        }
        DisplayScale._Show(message)
    }

    ; ---------------- Internals                     ------------------------------

    static _Flush(key, monitors) {
        if DisplayScale._timers.Has(key)
            DisplayScale._timers.Delete(key)
        message := "Display Scaling:"
        changed := 0
        for i, m in monitors {
            steps := DisplayScale._pending.Has(m) ? DisplayScale._pending[m] : 0
            if (steps = 0)
                continue
            DisplayScale._pending[m] := 0
            next := DisplayScale.StepBy(DisplayScale.Get(m), steps)
            DisplayScale.Set(next, m)
            message .= Format("`nMonitor {1}: {2}%", m, next)
            changed++
            ; SetDPI.exe misbehaves when invoked back-to-back.
            if (i < monitors.Length)
                Sleep(100)
        }
        if (changed)
            DisplayScale._Show(message)
    }

    static _ValidateMonitor(monitor) {
        if !IsInteger(monitor)
            throw ValueError("Monitor index must be an integer.")
        count := MonitorGetCount()
        if (monitor < 1 || monitor > count)
            throw ValueError(Format("Monitor index must be between 1 and {1}.", count))
        return Integer(monitor)
    }

    static _Exe() {
        path := DisplayScale.SetDpiPath
        if (path = "" || !FileExist(path))
            throw Error("SetDpi.exe not found. Set modules.displayScale.setDpiPath in your config (current: '" path "').")
        return path
    }

    static _Run(needOutput, args*) {
        cmd := '"' DisplayScale._Exe() '"'
        for arg in args {
            if (arg != "")
                cmd .= " " arg
        }
        if (!needOutput)
            return { stdout: "", exitCode: RunWait(cmd, , "Hide") }
        tmp := A_Temp "\setdpi_" A_TickCount ".txt"
        exitCode := RunWait(A_ComSpec ' /C "' cmd ' > "' tmp '" 2>&1"', , "Hide")
        stdout := FileExist(tmp) ? FileRead(tmp) : ""
        try FileDelete(tmp)
        return { stdout: stdout, exitCode: exitCode }
    }

    static _Show(message) => Toast.ShowToast({ fadeDelay: 2000, size: 12, width: 200 }, { text: message })
}
