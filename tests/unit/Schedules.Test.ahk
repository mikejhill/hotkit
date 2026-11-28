#Requires AutoHotkey v2.0

class Schedules_Tests {
    static Runs := []

    static Setup() {
        StatusLog.Path := A_Temp "\hotkit-schedules-" A_TickCount ".log"
        Schedules.Reset([])
        Schedules.Machine := "TESTPC"
        Schedules.Restarting := false
        Schedules_Tests.Runs := []
        Schedules.Runner := (spec, trigger) => Schedules_Tests.Runs.Push(spec.name ":" trigger)
        ActionRegistry.Register("test.act", (*) => 0)
    }

    static Teardown() {
        Schedules.Reset([])
        Schedules.Runner := ""
        Schedules.Machine := A_ComputerName
        ActionRegistry.Unregister("test.act")
        try FileDelete(StatusLog.Path)
        StatusLog.Path := ""
    }

    static Add(text, source := "test") => Schedules.Add(Config.FromText(text).data, source)

    static Problem() => Schedules.problems.Length ? Schedules.problems[Schedules.problems.Length] : ""

    static Test_ParseDuration() {
        Assert.Equal(90000, Schedules.ParseDuration("90s"))
        Assert.Equal(900000, Schedules.ParseDuration("15m"))
        Assert.Equal(5400000, Schedules.ParseDuration("1h30m"))
        Assert.Equal(5400000, Schedules.ParseDuration("1h 30m"))
        Assert.Equal(86400000 + 2000, Schedules.ParseDuration("1D2S"))
        Assert.Throws(() => Schedules.ParseDuration(""), "duration")
        Assert.Throws(() => Schedules.ParseDuration("15"), "duration")
        Assert.Throws(() => Schedules.ParseDuration(15), "duration")
        Assert.Throws(() => Schedules.ParseDuration("30m1h"), "duration")
        Assert.Throws(() => Schedules.ParseDuration("0s"), "longer than zero")
    }

    static Test_EventNamesAreCanonical() {
        Assert.Equal("pluggedIn", Schedules.EventName("PLUGGEDIN"))
        Assert.Equal("unlock", Schedules.EventName("unlock"))
        Assert.Throws(() => Schedules.EventName("boot"), "unknown event 'boot'")
    }

    static Test_SessionAndPowerCodes() {
        Assert.Equal("lock", Schedules.SessionEvent(7))
        Assert.Equal("unlock", Schedules.SessionEvent(8))
        Assert.Equal("remoteConnect", Schedules.SessionEvent(3))
        Assert.Equal("remoteDisconnect", Schedules.SessionEvent(4))
        Assert.Equal("", Schedules.SessionEvent(5))
        Assert.Equal("sleep", Schedules.PowerEvent(0x4))
        Assert.Equal("resume", Schedules.PowerEvent(0x12))
        Assert.Equal("", Schedules.PowerEvent(0x7), "PBT_APMRESUMESUSPEND would double resume")
        Assert.Equal("power", Schedules.PowerEvent(0xA))
    }

    static Test_PowerSourceTransitions() {
        Assert.Equal("pluggedIn", Schedules.PowerSourceEvent(0, 1))
        Assert.Equal("unplugged", Schedules.PowerSourceEvent(1, 0))
        Assert.Equal("", Schedules.PowerSourceEvent(1, 1))
        Assert.Equal("", Schedules.PowerSourceEvent(255, 1), "unknown before")
        Assert.Equal("", Schedules.PowerSourceEvent(0, 255))
    }

    static Test_AddsCronEveryAndEvents() {
        s := Schedules_Tests.Add('{ "name": "n", "cron": ["0 7 * * *", "@hourly"], "every": "1h", "on": ["Lock", "unlock"], "action": "test.act", "args": [1] }')
        Assert.Equal(0, Schedules.problems.Length)
        Assert.Equal("n", s.name)
        Assert.Equal(2, s.crons.Length)
        Assert.Equal(3600000, s.every)
        Assert.True(s.events.Has("lock"))
        Assert.True(s.events.Has("unlock"))
        Assert.Equal([1], s.args)
    }

    static Test_DefaultNameIsSource() {
        s := Schedules_Tests.Add('{ "on": "startup", "action": "test.act" }', "schedules[2]")
        Assert.Equal("schedules[2]", s.name)
    }

    static Test_ReportsProblems() {
        cases := Map(
            '{ "action": "test.act" }', "needs 'cron', 'every', or 'on'",
            '{ "on": "startup" }', "needs 'action'",
            '{ "on": "boot", "action": "test.act" }', "unknown event 'boot'",
            '{ "on": [], "action": "test.act" }', "'on' is an empty list",
            '{ "cron": "* * *", "action": "test.act" }', "5 fields",
            '{ "cron": "0 0 31 2 *", "action": "test.act" }', "never matches",
            '{ "every": "25d", "action": "test.act" }', "at most 24 days",
            '{ "every": 5, "action": "test.act" }', "'every' must be a duration",
            '{ "on": "startup", "catchUp": true, "action": "test.act" }', "'catchUp' needs 'cron'",
            '{ "every": "1h", "delay": "5s", "action": "test.act" }', "'delay' applies to 'on' events",
            '{ "on": "exit", "delay": "5s", "action": "test.act" }', "can't be used with 'exit'",
            '{ "on": ["unlock", "sleep"], "delay": "5s", "action": "test.act" }', "can't be used with 'sleep'",
            '{ "on": "lock", "idleAfter": "5m", "action": "test.act" }', "'idleAfter' needs",
            '{ "on": "idle", "idleAfter": "5s", "action": "test.act" }', "at least 10s",
            '{ "on": "startup", "action": "test.act", "when": "now" }', "unknown field 'when'",
            '{ "on": "startup", "action": "test.act", "machines": [] }', "'machines' must be",
            '{ "on": "startup", "action": "test.act", "name": 5 }', "'name' must be a string")
        for text, fragment in cases {
            Schedules.Reset([])
            Assert.Equal("", Schedules_Tests.Add(text), text)
            Assert.Equal(1, Schedules.problems.Length, text)
            Assert.Contains(Schedules_Tests.Problem(), fragment)
        }
    }

    static Test_ProblemNamesTheSchedule() {
        Schedules_Tests.Add('{ "name": "dim", "on": "nope", "action": "test.act" }', "schedules[3]")
        Assert.Contains(Schedules_Tests.Problem(), "schedules[3] (dim): ")
    }

    static Test_DuplicateNamesAreRejected() {
        Schedules_Tests.Add('{ "name": "a", "on": "lock", "action": "test.act" }')
        Assert.Equal("", Schedules_Tests.Add('{ "name": "A", "on": "unlock", "action": "test.act" }'))
        Assert.Contains(Schedules_Tests.Problem(), "already named 'A'")
    }

    static Test_DisabledAndOtherMachinesAreSkippedQuietly() {
        Assert.Equal("", Schedules_Tests.Add('{ "on": "lock", "action": "test.act", "enabled": false }'))
        Assert.Equal("", Schedules_Tests.Add('{ "on": "lock", "action": "test.act", "machines": ["OTHER"] }'))
        Assert.Equal(0, Schedules.problems.Length)
        Assert.Equal(0, Schedules.specs.Length)
        Assert.True(IsObject(Schedules_Tests.Add('{ "on": "lock", "action": "test.act", "machines": ["other", "testpc"] }')))
        Assert.True(IsObject(Schedules_Tests.Add('{ "on": "lock", "action": "test.act", "machines": "TestPC", "name": "b" }')))
    }

    static Test_ValidateReportsUnknownAction() {
        Schedules_Tests.Add('{ "name": "x", "on": "lock", "action": "no.such" }', "schedules[1]")
        Schedules.Validate()
        Assert.Equal("schedules[1] (x): unknown action 'no.such'.", Schedules_Tests.Problem())
    }

    static Test_LoadConfigRequiresList() {
        Schedules.LoadConfig(Config.FromText('{ "schedules": {} }'))
        Assert.Contains(Schedules_Tests.Problem(), "must be a list")
        Schedules.Reset([])
        Schedules.LoadConfig(Config.FromText('{ "schedules": [{ "on": "lock", "action": "test.act" }] }'))
        Assert.Equal("schedules[1]", Schedules.specs[1].name)
    }

    static Test_FireRunsMatchingSchedulesAndHandlers() {
        Schedules_Tests.Add('{ "name": "a", "on": ["lock", "unlock"], "action": "test.act" }')
        Schedules_Tests.Add('{ "name": "b", "on": "unlock", "action": "test.act" }')
        Schedules.On("Unlock", (event) => Schedules_Tests.Runs.Push("handler:" event))
        Schedules.Fire("unlock")
        Assert.Equal(["a:unlock", "b:unlock", "handler:unlock"], Schedules_Tests.Runs)
        Schedules.Fire("lock")
        Assert.Equal("a:lock", Schedules_Tests.Runs[4])
    }

    static Test_OnRejectsUnknownEventAndNonCallable() {
        Assert.Throws(() => Schedules.On("boot", (*) => 0), "unknown event")
        Assert.Throws(() => Schedules.On("lock", "nope"), "not callable")
    }

    static Test_ExitSkippedWhileRestarting() {
        Schedules_Tests.Add('{ "name": "bye", "on": "exit", "action": "test.act" }')
        Schedules.Restarting := true
        Schedules._Exit()
        Assert.Equal(0, Schedules_Tests.Runs.Length)
        Schedules.Restarting := false
        Schedules._Exit()
        Assert.Equal(["bye:exit"], Schedules_Tests.Runs)
    }

    static Test_TickRunsCronOncePerMinute() {
        s := Schedules_Tests.Add('{ "name": "c", "cron": "30 7 * * *", "action": "test.act" }')
        s.next := [s.crons[1].Next("20261127070000")]
        Schedules.Tick("20261127072900")
        Assert.Equal(0, Schedules_Tests.Runs.Length)
        Schedules.Tick("20261127073000")
        Schedules.Tick("20261127073045")
        Assert.Equal(["c:cron"], Schedules_Tests.Runs)
        Assert.Equal("20261128073000", s.next[1])
    }

    static Test_TickRunsScheduleOnceWhenTwoCronsMatch() {
        s := Schedules_Tests.Add('{ "name": "c", "cron": ["0 * * * *", "0 8 * * *"], "action": "test.act" }')
        s.next := [s.crons[1].Next("20261127075900"), s.crons[2].Next("20261127075900")]
        Schedules.Tick("20261127080000")
        Assert.Equal(["c:cron"], Schedules_Tests.Runs)
    }

    static Test_TickSkipsMissedTimeWithoutCatchUp() {
        s := Schedules_Tests.Add('{ "name": "c", "cron": "0 19 * * *", "action": "test.act" }')
        s.next := [s.crons[1].Next("20261127180000")]
        Schedules.Tick("20261127180000")
        Schedules.Tick("20261127210500")
        Assert.Equal(0, Schedules_Tests.Runs.Length)
        Assert.Equal("20261128190000", s.next[1])
    }

    static Test_TickCatchesUpMissedTimeOnce() {
        s := Schedules_Tests.Add('{ "name": "c", "cron": "0 * * * *", "catchUp": true, "action": "test.act" }')
        s.next := [s.crons[1].Next("20261127180000")]
        Schedules.Tick("20261127180000")
        Schedules.Tick("20261127210500")
        Assert.Equal(["c:cron (catch-up)"], Schedules_Tests.Runs, "three hours missed, one run")
        Assert.Equal("20261127220000", s.next[1])
    }

    static Test_TickStartsOverWhenClockMovesBack() {
        s := Schedules_Tests.Add('{ "name": "c", "cron": "30 7 * * *", "action": "test.act" }')
        s.next := [s.crons[1].Next("20261127080000")]
        Schedules.Tick("20261127080000")
        Schedules.Tick("20261127060000")
        Assert.Equal("20261127073000", s.next[1])
        Schedules.Tick("20261127073000")
        Assert.Equal(["c:cron"], Schedules_Tests.Runs)
    }

    static Test_PollIdleFiresOnTransitions() {
        Schedules_Tests.Add('{ "name": "dim", "on": ["idle", "active"], "idleAfter": "1m", "action": "test.act" }')
        Schedules_Tests.Add('{ "name": "late", "on": "idle", "idleAfter": "5m", "action": "test.act" }')
        Schedules.PollIdle(30000)
        Assert.Equal(0, Schedules_Tests.Runs.Length)
        Schedules.PollIdle(60000)
        Schedules.PollIdle(90000)
        Assert.Equal(["dim:idle"], Schedules_Tests.Runs)
        Schedules.PollIdle(300000)
        Assert.Equal("late:idle", Schedules_Tests.Runs[2])
        Schedules.PollIdle(100)
        Assert.Equal(["dim:idle", "late:idle", "dim:active"], Schedules_Tests.Runs, "late has no active")
    }

    static Test_RunNowByName() {
        Schedules_Tests.Add('{ "name": "Evening", "on": "lock", "action": "test.act" }')
        Schedules.RunNow("evening")
        Assert.Equal(["Evening:manual"], Schedules_Tests.Runs)
        Assert.Throws(() => Schedules.RunNow("nope"), "No schedule named 'nope'")
    }

    static Test_RunInvokesActionWithArgs() {
        got := []
        ActionRegistry.Register("test.args", (a, b) => got.Push(a, b))
        Schedules.Runner := ""
        s := Schedules_Tests.Add('{ "on": "lock", "action": "test.args", "args": ["x", 2] }')
        Schedules.Fire("lock")
        ActionRegistry.Unregister("test.args")
        Assert.Equal(["x", 2], got)
    }

    static Test_ThemeModeParsesLightAndDark() {
        Assert.Equal(1, DesktopModule.ThemeMode("light"))
        Assert.Equal(0, DesktopModule.ThemeMode("Dark"))
        Assert.Throws(() => DesktopModule.ThemeMode("blue"), "'light' or 'dark'")
    }
}

TestRunner.Add(Schedules_Tests)
