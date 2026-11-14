#Requires AutoHotkey v2.0

class Power_Tests {
    static S(awake := false, screen := false, unlocked := false) {
        return { keepAwake: awake, keepScreenOn: screen, keepUnlocked: unlocked }
    }

    static Test_FlagsAllOffClearsRequests() {
        Assert.Equal(0x80000000, PowerModule.Flags(Power_Tests.S()))
    }

    static Test_FlagsKeepAwakeHoldsSystemOnly() {
        Assert.Equal(0x80000001, PowerModule.Flags(Power_Tests.S(true)))
    }

    static Test_FlagsScreenOnAndUnlockedHoldDisplayAndSystem() {
        Assert.Equal(0x80000003, PowerModule.Flags(Power_Tests.S(false, true)))
        Assert.Equal(0x80000003, PowerModule.Flags(Power_Tests.S(false, false, true)))
        Assert.Equal(0x80000003, PowerModule.Flags(Power_Tests.S(true, true, true)))
    }

    static Test_FlagsDropDisplayWhileMonitorsAreOff() {
        Assert.Equal(0x80000001, PowerModule.Flags(Power_Tests.S(false, true), true), "screen on: stay awake only")
        Assert.Equal(0x80000001, PowerModule.Flags(Power_Tests.S(false, false, true), true))
        Assert.Equal(0x80000000, PowerModule.Flags(Power_Tests.S(), true))
    }

    static Test_SummaryNamesStrongestToggle() {
        Assert.Equal("", PowerModule.Summary(Power_Tests.S()))
        Assert.Equal("Keep Awake", PowerModule.Summary(Power_Tests.S(true)))
        Assert.Equal("Keep Screen On", PowerModule.Summary(Power_Tests.S(true, true)))
        Assert.Equal("Keep Unlocked", PowerModule.Summary(Power_Tests.S(true, true, true)))
    }

    static Test_SummaryShowsEndTimeOfStrongestToggle() {
        ends := { keepAwake: "20261114013000", keepScreenOn: "", keepUnlocked: "20261114143000" }
        Assert.Equal("Keep Unlocked until 2:30 PM", PowerModule.Summary(Power_Tests.S(true, false, true), ends))
        Assert.Equal("Keep Awake until 1:30 AM", PowerModule.Summary(Power_Tests.S(true), ends))
        Assert.Equal("Keep Screen On", PowerModule.Summary(Power_Tests.S(true, true), ends), "no limit on the strongest")
    }

    static Test_EndTimeFromMinutes() {
        Assert.Equal("", PowerModule.EndTime(0, "20261114010000"))
        Assert.Equal("", PowerModule.EndTime("", "20261114010000"))
        Assert.Equal("20261114013000", PowerModule.EndTime(30, "20261114010000"))
        Assert.Equal("20261114090000", PowerModule.EndTime("480", "20261114010000"))
        Assert.Equal("20261114010030", PowerModule.EndTime(0.5, "20261114010000"))
        Assert.Equal("20261114023000", PowerModule.EndTime("20261114023000", "20261114010000"), "end time passes through")
    }

    static Test_EndTimeRejectsBadMinutes() {
        Assert.Throws(() => PowerModule.EndTime(-5, "20261114010000"), "positive number of minutes")
        Assert.Throws(() => PowerModule.EndTime("abc", "20261114010000"), "positive number of minutes")
    }

    static Test_OnText() {
        Assert.Equal("On.", PowerModule.OnText(""))
        Assert.Equal("On until 9:05 AM.", PowerModule.OnText("20261114090500"))
    }

    static Test_ExpiredListsFinishedToggles() {
        ends := { keepAwake: "20261114010000", keepScreenOn: "20261114020000", keepUnlocked: "" }
        Assert.Equal(["keepAwake"], PowerModule.Expired(ends, "20261114010000"))
        Assert.Equal(["keepAwake", "keepScreenOn"], PowerModule.Expired(ends, "20261114030000"))
        Assert.Equal([], PowerModule.Expired(ends, "20261114005959"))
    }

    static Test_HandoffUntil() {
        Assert.Equal("none", PowerModule.HandoffUntil("", "20261114010000"))
        Assert.Equal("none", PowerModule.HandoffUntil("junk", "20261114010000"))
        Assert.Equal("active", PowerModule.HandoffUntil("20261114010001", "20261114010000"))
        Assert.Equal("expired", PowerModule.HandoffUntil("20261114010000", "20261114010000"))
    }

    static Test_DurationLabels() {
        Assert.Equal("For &30 minutes", PowerModule.DurationLabel(30))
        Assert.Equal("For &1 hour", PowerModule.DurationLabel(60))
        Assert.Equal("For &8 hours", PowerModule.DurationLabel(480))
        Assert.Equal("For &90 minutes", PowerModule.DurationLabel(90))
    }

    static Test_TitlesDropMenuMarkup() {
        Assert.Equal("Keep Awake", PowerModule.Title("keepAwake"))
        Assert.Equal("Keep Screen On", PowerModule.Title("keepScreenOn"))
        Assert.Equal("Keep Unlocked", PowerModule.Title("keepUnlocked"))
    }

    static Test_LockPolicyNoneEnforced() {
        Assert.Equal("", PowerModule.LockPolicy({ inactivityTimeoutSecs: "", screenSaveActive: "", screenSaverIsSecure: "" }))
        Assert.Equal("", PowerModule.LockPolicy({ inactivityTimeoutSecs: 0, screenSaveActive: "0", screenSaverIsSecure: "0" }))
    }

    static Test_LockPolicyInactivityLimitRefuses() {
        reason := PowerModule.LockPolicy({ inactivityTimeoutSecs: 900, screenSaveActive: "", screenSaverIsSecure: "" })
        Assert.Contains(reason, "900 seconds")
        Assert.Contains(reason, "Keep Screen On still works")
    }

    static Test_LockPolicyScreenSaverPolicyRefuses() {
        Assert.Contains(PowerModule.LockPolicy({ inactivityTimeoutSecs: "", screenSaveActive: "1", screenSaverIsSecure: "" }), "screen saver")
        Assert.Contains(PowerModule.LockPolicy({ inactivityTimeoutSecs: "", screenSaveActive: "", screenSaverIsSecure: "1" }), "screen saver")
    }

    static Test_LockPolicyMdmInactivityRefuses() {
        reason := PowerModule.LockPolicy({ inactivityTimeoutSecs: "", screenSaveActive: "", screenSaverIsSecure: "", mdmMaxInactivityMinutes: 15 })
        Assert.Contains(reason, "MDM")
        Assert.Contains(reason, "15 minutes")
        Assert.Equal("", PowerModule.LockPolicy({ inactivityTimeoutSecs: "", screenSaveActive: "", screenSaverIsSecure: "", mdmMaxInactivityMinutes: 0 }))
    }

    static Test_InputSinceCountsAnyInputAfterOff() {
        Assert.False(PowerModule.InputSince(1000, 5000, 4000), "idle since the monitors went off")
        Assert.False(PowerModule.InputSince(1000, 5000, 4600), "last input came before")
        Assert.True(PowerModule.InputSince(1000, 5000, 200), "recent input")
        Assert.True(PowerModule.InputSince(1000, 5000, 3800), "input right after off still counts")
        Assert.True(PowerModule.InputSince(1000, 1300, 100))
    }

    static Test_HandoffFreshness() {
        Assert.True(PowerModule.HandoffFresh("20261114010000", "20261114010100"))
        Assert.True(PowerModule.HandoffFresh("20261114010000", "20261114010000"))
        Assert.False(PowerModule.HandoffFresh("20261114010000", "20261114010201"), "older than two minutes")
        Assert.False(PowerModule.HandoffFresh("20261114010100", "20261114010000"), "from the future")
        Assert.False(PowerModule.HandoffFresh("", "20261114010000"))
        Assert.False(PowerModule.HandoffFresh("junk", "20261114010000"))
    }

    static Test_TrayTipListsStatuses() {
        Assert.Equal("hotkit 1.2.0", Tray.Tip("1.2.0", []))
        Assert.Equal("hotkit 1.2.0: Keep Unlocked", Tray.Tip("1.2.0", ["Keep Unlocked"]))
        Assert.Equal("hotkit 1.2.0: a, b", Tray.Tip("1.2.0", ["a", "b"]))
    }

    static Test_UnknownToggleThrows() {
        Assert.Throws(() => PowerModule.Set("keepWarm", true), "Unknown power toggle")
    }
}
TestRunner.Add(Power_Tests)
