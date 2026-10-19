#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Stopwatch\StopwatchClock.ahk

; Example plugin: a stopwatch with laps, shown in a toast.
;
;   "plugins": { "stopwatch": { "showLaps": 3 } }
;
; Shows: a plugin that keeps state between actions; every setting is optional.
App.AddPlugin("stopwatch", (settings) => StopwatchPlugin.Init(settings))

class StopwatchPlugin {
    static Clock := ""
    static ShowLaps := 3

    static Init(settings) {
        StopwatchPlugin.Clock := StopwatchClock.New()
        StopwatchPlugin.ShowLaps := MapGet(settings, "showLaps", 3)

        reg := (id, fn, desc) => ActionRegistry.Register(id, fn, { module: "plugin:stopwatch", description: desc })
        reg("stopwatch.toggle", (*) => StopwatchPlugin.Toggle(), "Start or pause the stopwatch")
        reg("stopwatch.lap", (*) => StopwatchPlugin.Lap(), "Record a lap")
        reg("stopwatch.reset", (*) => StopwatchPlugin.Reset(), "Stop the stopwatch and clear its laps")
        reg("stopwatch.show", (*) => StopwatchPlugin.Show(), "Show the elapsed time and recent laps")
    }

    static Toggle() {
        c := StopwatchPlugin.Clock
        if c.running
            StopwatchClock.Pause(c, A_TickCount)
        else
            StopwatchClock.Start(c, A_TickCount)
        StopwatchPlugin.Show()
    }

    static Lap() {
        StopwatchClock.Lap(StopwatchPlugin.Clock, A_TickCount)
        StopwatchPlugin.Show()
    }

    static Reset() {
        StopwatchClock.Reset(StopwatchPlugin.Clock)
        StopwatchPlugin.Show()
    }

    static Show() {
        c := StopwatchPlugin.Clock
        lines := [{ text: StopwatchClock.Format(StopwatchClock.Elapsed(c, A_TickCount)), size: 20, bold: true },
            { text: c.running ? "Running" : "Paused", size: 11 }]
        laps := c.laps
        first := Max(1, laps.Length - StopwatchPlugin.ShowLaps + 1)
        loop laps.Length - first + 1 {
            i := first + A_Index - 1
            lines.Push({ text: "Lap " i "  " StopwatchClock.Format(laps[i]), size: 11 })
        }
        Toast.ShowToast({ fadeDelay: 2000, width: 180 }, lines*)
    }
}
