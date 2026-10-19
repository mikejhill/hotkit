#Requires AutoHotkey v2.0

; Decisions for the BreakReminder example plugin. No UI or timers, so it can be unit tested.
class BreakSchedule {
    static ValidInterval(value) {
        if !(IsNumber(value) && value > 0)
            throw ValueError("intervalMinutes must be a positive number.")
        return value + 0
    }

    ; Whole minutes until the next break, rounded up; 0 once it is due.
    static MinutesLeft(startTick, nowTick, intervalMinutes) {
        left := intervalMinutes * 60000 - (nowTick - startTick)
        return left > 0 ? Ceil(left / 60000) : 0
    }

    static Describe(paused, minutesLeft) {
        if paused
            return "Break reminders paused"
        if (minutesLeft <= 0)
            return "Break due now"
        return "Next break in " minutesLeft (minutesLeft = 1 ? " minute" : " minutes")
    }
}
