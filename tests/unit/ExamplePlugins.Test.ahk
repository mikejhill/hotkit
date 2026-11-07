#Requires AutoHotkey v2.0

; Helpers of the plugins in examples/plugins. The plugins themselves are loaded
; by the integration stage of tools/test.py.
class ExamplePlugins_Tests {
    static Test_BreakIntervalMustBePositive() {
        Assert.Equal(25, BreakSchedule.ValidInterval(25))
        Assert.Equal(0.5, BreakSchedule.ValidInterval(0.5))
        Assert.Throws(() => BreakSchedule.ValidInterval(0), "positive")
        Assert.Throws(() => BreakSchedule.ValidInterval(-5), "positive")
        Assert.Throws(() => BreakSchedule.ValidInterval("soon"), "positive")
    }

    static Test_BreakMinutesLeftRoundsUp() {
        Assert.Equal(50, BreakSchedule.MinutesLeft(1000, 1000, 50))
        Assert.Equal(50, BreakSchedule.MinutesLeft(1000, 1001, 50))
        Assert.Equal(1, BreakSchedule.MinutesLeft(0, 49 * 60000 + 1, 50))
        Assert.Equal(0, BreakSchedule.MinutesLeft(0, 50 * 60000, 50))
        Assert.Equal(0, BreakSchedule.MinutesLeft(0, 99 * 60000, 50))
    }

    static Test_BreakDescribe() {
        Assert.Equal("Break reminders paused", BreakSchedule.Describe(true, 10))
        Assert.Equal("Break due now", BreakSchedule.Describe(false, 0))
        Assert.Equal("Next break in 1 minute", BreakSchedule.Describe(false, 1))
        Assert.Equal("Next break in 12 minutes", BreakSchedule.Describe(false, 12))
    }

    static Test_NoteLineIsOneTrimmedLine() {
        Assert.Equal("2026-01-02 03:04  buy milk`n", NoteFormat.Line("  buy milk ", "2026-01-02 03:04"))
        Assert.Equal("t  one two three`n", NoteFormat.Line("one`r`n  two`nthree", "t"))
    }

    static Test_BlankNoteIsSkipped() {
        Assert.Equal("", NoteFormat.Line("", "t"))
        Assert.Equal("", NoteFormat.Line(" `r`n `t", "t"))
    }

    static Test_StopwatchStartPauseResume() {
        c := StopwatchClock.New()
        Assert.Equal(0, StopwatchClock.Elapsed(c, 500))
        StopwatchClock.Start(c, 1000)
        StopwatchClock.Start(c, 1500)
        Assert.Equal(700, StopwatchClock.Elapsed(c, 1700), "second Start keeps the first start tick")
        StopwatchClock.Pause(c, 2000)
        StopwatchClock.Pause(c, 2500)
        Assert.Equal(1000, StopwatchClock.Elapsed(c, 9000), "paused time is not counted")
        StopwatchClock.Start(c, 10000)
        Assert.Equal(1250, StopwatchClock.Elapsed(c, 10250))
    }

    static Test_StopwatchLapsAndReset() {
        c := StopwatchClock.New()
        Assert.Equal(0, StopwatchClock.Lap(c, 0), "no lap before anything elapsed")
        StopwatchClock.Start(c, 0)
        Assert.Equal(300, StopwatchClock.Lap(c, 300))
        Assert.Equal(200, StopwatchClock.Lap(c, 500))
        Assert.Equal(0, StopwatchClock.Lap(c, 500), "no empty lap")
        Assert.Equal([300, 200], c.laps)
        StopwatchClock.Reset(c)
        Assert.False(c.running)
        Assert.Equal(0, StopwatchClock.Elapsed(c, 9999))
        Assert.Equal(0, c.laps.Length)
        StopwatchClock.Start(c, 1000)
        Assert.Equal(100, StopwatchClock.Lap(c, 1100), "laps restart from zero after reset")
    }

    static Test_StopwatchFormat() {
        Assert.Equal("00:00.0", StopwatchClock.Format(0))
        Assert.Equal("00:00.0", StopwatchClock.Format(-5))
        Assert.Equal("00:00.9", StopwatchClock.Format(999))
        Assert.Equal("01:05.4", StopwatchClock.Format(65432))
        Assert.Equal("59:59.9", StopwatchClock.Format(3599999))
        Assert.Equal("1:02:03.4", StopwatchClock.Format(3723400))
    }
}
TestRunner.Add(ExamplePlugins_Tests)
