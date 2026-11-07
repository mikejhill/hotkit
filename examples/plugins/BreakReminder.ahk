#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\BreakReminder\BreakSchedule.ahk

; Example plugin: shows a reminder to take a break every few minutes.
;
;   "plugins": { "breakReminder": { "intervalMinutes": 50, "message": "Stand up and stretch" } }
;
; Shows: settings with defaults, invalid settings reported as config problems,
; a timer started only in "run" mode, and App.OnReady.
App.AddPlugin("breakReminder", (settings) => BreakReminderPlugin.Init(settings))

class BreakReminderPlugin {
    static Interval := 50
    static Message := ""
    static Paused := false
    static StartTick := 0
    static Tick := (*) => BreakReminderPlugin.Remind()

    static Init(settings) {
        ; A thrown error here is listed by --check and the tray; the rest of the app still starts.
        BreakReminderPlugin.Interval := BreakSchedule.ValidInterval(MapGet(settings, "intervalMinutes", 50))
        BreakReminderPlugin.Message := MapGet(settings, "message", "Time for a break")

        reg := (id, fn, desc) => ActionRegistry.Register(id, fn, { module: "plugin:breakReminder", description: desc })
        reg("breakReminder.now", (*) => BreakReminderPlugin.Remind(), "Show the break reminder now and restart the countdown")
        reg("breakReminder.togglePause", (*) => BreakReminderPlugin.TogglePause(), "Pause or resume break reminders")
        reg("breakReminder.status", (*) => BreakReminderPlugin.ShowStatus(), "Show the time until the next break")

        ; --check and --list-actions load plugins too; start timers only when running.
        if (App.Mode = "run")
            App.OnReady(() => BreakReminderPlugin.Restart())
    }

    static Remind() {
        Toast.ShowToast({ fadeDelay: 5000 }, { text: BreakReminderPlugin.Message, size: 16, bold: true })
        if !BreakReminderPlugin.Paused
            BreakReminderPlugin.Restart()
    }

    static Restart() {
        BreakReminderPlugin.StartTick := A_TickCount
        SetTimer(BreakReminderPlugin.Tick, Round(BreakReminderPlugin.Interval * 60000))
    }

    static TogglePause() {
        BreakReminderPlugin.Paused := !BreakReminderPlugin.Paused
        if BreakReminderPlugin.Paused
            SetTimer(BreakReminderPlugin.Tick, 0)
        else
            BreakReminderPlugin.Restart()
        BreakReminderPlugin.ShowStatus()
    }

    static ShowStatus() {
        left := BreakSchedule.MinutesLeft(BreakReminderPlugin.StartTick, A_TickCount, BreakReminderPlugin.Interval)
        Toast.ShowToast({ fadeDelay: 1500 }, BreakSchedule.Describe(BreakReminderPlugin.Paused, left))
    }
}
