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
        Schedules.Delayer := (fn, ms) => SetTimer(fn, -ms)
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
        Assert.Equal(1, s.steps.Length)
        Assert.Equal("test.act", s.steps[1].action)
        Assert.Equal([1], s.steps[1].args)
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
            '{ "on": "startup", "action": "test.act", "name": 5 }', "'name' must be a string",
            '{ "on": "startup", "action": [] }', "'action' must be an action id string",
            '{ "on": "startup", "action": {} }', "'action' must be an action id string",
            '{ "on": "startup", "delay": "25d", "action": "test.act" }', "'delay' can be at most 24 days",
            '{ "on": "startup" }', "needs 'action' or 'actions'",
            '{ "on": "startup", "action": "test.act", "actions": ["test.act"] }', "not both",
            '{ "on": "startup", "args": [1], "actions": ["test.act"] }', "not both",
            '{ "on": "startup", "actions": [] }', "'actions' must be a non-empty list",
            '{ "on": "startup", "actions": "test.act" }', "'actions' must be a non-empty list",
            '{ "on": "startup", "actions": [5] }', "actions[1]: use an action id",
            '{ "on": "startup", "actions": ["test.act", { "args": [1] }] }', "actions[2]: use an action id",
            '{ "on": "startup", "actions": [{ "action": "test.act", "when": 1 }] }', "actions[1]: unknown field 'when'",
            '{ "on": "startup", "actions": [{ "wait": "1s", "action": "test.act" }] }', "actions[1]: a wait step takes only 'wait'",
            '{ "on": "startup", "actions": ["test.act", { "wait": "5" }] }', "'actions[2].wait' must be a duration",
            '{ "on": "startup", "actions": ["test.act", { "wait": "25d" }] }', "'wait' can be at most 24 days",
            '{ "on": "startup", "actions": [{ "wait": "1s" }] }', "at least one action, not only waits",
            '{ "on": "exit", "actions": ["test.act", { "wait": "1s" }, "test.act"] }', "'wait' steps can't be used with 'exit'",
            '{ "on": ["lock", "sleep"], "actions": [{ "wait": "1s" }, "test.act"] }', "'wait' steps can't be used with 'sleep'")
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
        Assert.Equal(["c:cron (catch-up for 20261127210000)"], Schedules_Tests.Runs, "three hours missed, one run")
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

    static Test_TickRunsCurrentMinuteAfterGap() {
        s := Schedules_Tests.Add('{ "name": "h", "cron": "0 * * * *", "action": "test.act" }')
        s.next := [s.crons[1].Next("20261127065900")]
        Schedules.Tick("20261127070000")
        Schedules.Tick("20261127090000")
        Assert.Equal(["h:cron", "h:cron"], Schedules_Tests.Runs, "09:00 matches; the missed 08:00 doesn't add a run")
        Assert.Equal("20261127100000", s.next[1])
    }

    static Test_CatchUpRunsInTimeOrder() {
        dark := Schedules_Tests.Add('{ "name": "dark", "cron": "0 19 * * *", "catchUp": true, "action": "test.act" }')
        light := Schedules_Tests.Add('{ "name": "light", "cron": "0 7 * * *", "catchUp": true, "action": "test.act" }')
        dark.next := [dark.crons[1].Next("20261127060000")]
        light.next := [light.crons[1].Next("20261127060000")]
        Schedules.Tick("20261127060000")
        Schedules.Tick("20261127200000")
        Assert.Equal(["light:cron (catch-up for 20261127070000)", "dark:cron (catch-up for 20261127190000)"],
            Schedules_Tests.Runs)
    }

    static Test_CatchUpOrdersByLatestMissedTime() {
        hourly := Schedules_Tests.Add('{ "name": "hourly", "cron": "0 * * * *", "catchUp": true, "action": "test.act" }')
        once := Schedules_Tests.Add('{ "name": "once", "cron": "30 8 * * *", "catchUp": true, "action": "test.act" }')
        hourly.next := [hourly.crons[1].Next("20261127065900")]
        once.next := [once.crons[1].Next("20261127065900")]
        Schedules.Tick("20261127065900")
        Schedules.Tick("20261127094500")
        Assert.Equal(["once:cron (catch-up for 20261127083000)", "hourly:cron (catch-up for 20261127090000)"],
            Schedules_Tests.Runs)
    }

    static Test_CurrentRunGoesAfterCatchUp() {
        light := Schedules_Tests.Add('{ "name": "light", "cron": "0 7 * * *", "action": "test.act" }')
        dark := Schedules_Tests.Add('{ "name": "dark", "cron": "0 19 * * *", "catchUp": true, "action": "test.act" }')
        light.next := [light.crons[1].Next("20261126180000")]
        dark.next := [dark.crons[1].Next("20261126180000")]
        Schedules.Tick("20261126180000")
        Schedules.Tick("20261127070000")
        Assert.Equal(["dark:cron (catch-up for 20261126190000)", "light:cron"], Schedules_Tests.Runs)
    }

    static Test_LastBeforeFindsLatestAfterLongGap() {
        c := Cron.Parse("0-58 * * * *")
        Assert.Equal("20261204005800", Schedules.LastBefore(c, "20261126000000", "202612040059"))
    }

    static Test_RunSkipsReentry() {
        s := Schedules_Tests.Add('{ "name": "r", "on": "lock", "action": "test.act" }')
        Schedules.Runner := (spec, trigger) => (Schedules_Tests.Runs.Push(trigger), Schedules.Run(spec, "inner"))
        Schedules.Fire("lock")
        Assert.Equal(["lock"], Schedules_Tests.Runs)
        Assert.False(s.running)
    }

    static Test_SortByTimeIsStable() {
        out := Schedules.SortByTime([{ at: "2", n: "a" }, { at: "1", n: "b" }, { at: "2", n: "c" }])
        Assert.Equal("b", out[1].n)
        Assert.Equal("a", out[2].n)
        Assert.Equal("c", out[3].n)
    }

    static Test_ValidateReportsScheduleRunLoops() {
        ActionRegistry.Register("schedule.run", (*) => 0)
        Schedules_Tests.Add('{ "name": "a", "on": "lock", "action": "schedule.run", "args": ["b"] }', "schedules[1]")
        Schedules_Tests.Add('{ "name": "b", "on": "unlock", "action": "schedule.run", "args": ["A"] }', "schedules[2]")
        Schedules_Tests.Add('{ "name": "c", "on": "unlock", "action": "schedule.run", "args": ["a"] }', "schedules[3]")
        Schedules_Tests.Add('{ "name": "self", "on": "startup", "action": "schedule.run", "args": ["self"] }', "schedules[4]")
        Schedules.Validate()
        ActionRegistry.Unregister("schedule.run")
        Assert.Equal(3, Schedules.problems.Length, "c only leads into the loop")
        Assert.Equal(1, Schedules.specs.Length, "looping schedules are dropped")
        Assert.Equal("c", Schedules.specs[1].name)
        Assert.Equal("schedules[1] (a): schedule.run calls loop back: a -> b -> a.", Schedules.problems[1])
        Assert.Equal("schedules[2] (b): schedule.run calls loop back: b -> a -> b.", Schedules.problems[2])
        Assert.Equal("schedules[4] (self): schedule.run calls loop back: self -> self.", Schedules.problems[3])
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

    static Test_ParsesActionsList() {
        s := Schedules_Tests.Add('{ "on": "lock", "actions": ["test.act", { "wait": "1m30s" }, { "action": "test.act", "args": [5] }] }')
        Assert.Equal(0, Schedules.problems.Length)
        Assert.Equal(3, s.steps.Length)
        Assert.Equal("test.act", s.steps[1].action)
        Assert.Equal([], s.steps[1].args)
        Assert.Equal(90000, s.steps[2].wait)
        Assert.Equal([5], s.steps[3].args)
        Assert.Equal("test.act, wait 90s, test.act", Schedules.Describe(s.steps))
    }

    static Test_RunStepsInOrderWithWaits() {
        calls := []
        ActionRegistry.Register("test.one", (*) => calls.Push("one"))
        ActionRegistry.Register("test.two", (n) => calls.Push("two:" n))
        Schedules.Runner := ""
        Schedules.Delayer := (fn, ms) => (calls.Push("wait:" ms), fn.Call())
        Schedules_Tests.Add('{ "on": "unlock", "actions": ["test.one", { "wait": "2s" }, { "action": "test.two", "args": [7] }] }')
        Schedules.Fire("unlock")
        ActionRegistry.Unregister("test.one")
        ActionRegistry.Unregister("test.two")
        Assert.Equal(["one", "wait:2000", "two:7"], calls)
    }

    static Boom(calls, *) {
        calls.Push("boom")
        throw Error("nope")
    }

    static Test_FailedStepStopsTheRest() {
        calls := []
        errors := []
        ActionRegistry.Register("test.boom", Schedules_Tests.Boom.Bind(Schedules_Tests, calls))
        ActionRegistry.Register("test.after", (*) => calls.Push("after"))
        saved := ActionRegistry.OnError
        ActionRegistry.OnError := (id, e) => errors.Push(id ": " e.Message)
        Schedules.Runner := ""
        stop := Schedules_Tests.Add('{ "name": "stop", "on": "lock", "actions": ["test.boom", "test.after"] }')
        go := Schedules_Tests.Add('{ "name": "go", "on": "unlock", "continueOnError": true, "actions": ["test.boom", "test.after"] }')
        failedStop := Schedules.RunSteps(stop)
        failedGo := Schedules.RunSteps(go)
        ActionRegistry.OnError := saved
        ActionRegistry.Unregister("test.boom")
        ActionRegistry.Unregister("test.after")
        Assert.Equal(["boom", "boom", "after"], calls)
        Assert.Equal(["test.boom: nope", "test.boom: nope"], errors)
        Assert.Equal(1, failedStop)
        Assert.Equal(1, failedGo)
    }

    static Test_WaitHandsTheRestToATimer() {
        calls := []
        pending := []
        ActionRegistry.Register("test.one", (*) => calls.Push("one"))
        ActionRegistry.Register("test.two", (*) => calls.Push("two"))
        Schedules.Runner := ""
        Schedules.Delayer := (fn, ms) => pending.Push(fn)
        s := Schedules_Tests.Add('{ "on": "lock", "actions": ["test.one", { "wait": "2m" }, "test.two"] }')
        Schedules.Fire("lock")
        Assert.Equal(["one"], calls, "returns at the wait")
        Assert.True(s.running)
        Schedules.Fire("lock")
        Assert.Equal(["one"], calls, "a second trigger is skipped while waiting")
        pending[1].Call()
        ActionRegistry.Unregister("test.one")
        ActionRegistry.Unregister("test.two")
        Assert.Equal(["one", "two"], calls)
        Assert.False(s.running)
    }

    static Test_RunNowThrowsWhenAStepFails() {
        ActionRegistry.Register("test.boom", Schedules_Tests.Boom.Bind(Schedules_Tests, []))
        saved := ActionRegistry.OnError
        ActionRegistry.OnError := (*) => 0
        Schedules.Runner := ""
        Schedules_Tests.Add('{ "name": "child", "on": "lock", "actions": ["test.boom"] }')
        err := Assert.Throws(() => Schedules.RunNow("child"), "schedule 'child': 1 step failed")
        ActionRegistry.OnError := saved
        ActionRegistry.Unregister("test.boom")
    }

    static Test_ParentStopsWhenChildScheduleFails() {
        calls := []
        ActionRegistry.Register("test.boom", Schedules_Tests.Boom.Bind(Schedules_Tests, calls))
        ActionRegistry.Register("test.after", (*) => calls.Push("after"))
        ActionRegistry.Register("schedule.run", (name) => Schedules.RunNow(name))
        saved := ActionRegistry.OnError
        ActionRegistry.OnError := (id, e) => calls.Push("error:" id)
        Schedules.Runner := ""
        Schedules_Tests.Add('{ "name": "child", "on": "lock", "actions": ["test.boom"] }')
        Schedules_Tests.Add('{ "name": "parent", "on": "unlock", "actions": [{ "action": "schedule.run", "args": ["child"] }, "test.after"] }')
        Schedules.Fire("unlock")
        ActionRegistry.OnError := saved
        for id in ["test.boom", "test.after", "schedule.run"]
            ActionRegistry.Unregister(id)
        Assert.Equal(["boom", "error:test.boom", "error:schedule.run"], calls)
    }

    static Test_ExitScheduleCantReachAWait() {
        ActionRegistry.Register("schedule.run", (*) => 0)
        Schedules_Tests.Add('{ "name": "bye", "on": "exit", "actions": [{ "action": "schedule.run", "args": ["mid"] }] }', "schedules[1]")
        Schedules_Tests.Add('{ "name": "mid", "on": "lock", "action": "schedule.run", "args": ["slow"] }', "schedules[2]")
        Schedules_Tests.Add('{ "name": "slow", "on": "lock", "actions": ["test.act", { "wait": "1s" }, "test.act"] }', "schedules[3]")
        Schedules.Validate()
        ActionRegistry.Unregister("schedule.run")
        Assert.Equal(["schedules[1] (bye): runs 'slow', which has 'wait' steps; exit and sleep schedules can't wait."],
            Schedules.problems)
        Assert.Equal(2, Schedules.specs.Length)
    }

    static Test_ValidateChecksEveryStepAction() {
        Schedules_Tests.Add('{ "name": "x", "on": "lock", "actions": ["test.act", "no.such", { "action": "also.missing" }] }', "schedules[1]")
        Schedules.Validate()
        Assert.Equal(["schedules[1] (x): unknown action 'no.such'.", "schedules[1] (x): unknown action 'also.missing'."],
            Schedules.problems)
    }

    static Test_ValidateFindsLoopThroughLaterStep() {
        ActionRegistry.Register("schedule.run", (*) => 0)
        Schedules_Tests.Add('{ "name": "a", "on": "lock", "actions": ["test.act", { "action": "schedule.run", "args": ["b"] }] }', "schedules[1]")
        Schedules_Tests.Add('{ "name": "b", "on": "unlock", "actions": [{ "action": "schedule.run", "args": ["c"] }, { "action": "schedule.run", "args": ["a"] }] }', "schedules[2]")
        Schedules_Tests.Add('{ "name": "c", "on": "unlock", "action": "test.act" }', "schedules[3]")
        Schedules.Validate()
        ActionRegistry.Unregister("schedule.run")
        Assert.Equal("schedules[1] (a): schedule.run calls loop back: a -> b -> a.", Schedules.problems[1])
        Assert.Equal("schedules[2] (b): schedule.run calls loop back: b -> a -> b.", Schedules.problems[2])
        Assert.Equal(1, Schedules.specs.Length)
    }

    static Test_ThemeModeParsesLightAndDark() {
        Assert.Equal(1, DesktopModule.ThemeMode("light"))
        Assert.Equal(0, DesktopModule.ThemeMode("Dark"))
        Assert.Throws(() => DesktopModule.ThemeMode("blue"), "'light' or 'dark'")
    }
}

TestRunner.Add(Schedules_Tests)
