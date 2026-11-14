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
        Assert.Equal("keeping awake", PowerModule.Summary(Power_Tests.S(true)))
        Assert.Equal("keeping screen on", PowerModule.Summary(Power_Tests.S(true, true)))
        Assert.Equal("keeping unlocked", PowerModule.Summary(Power_Tests.S(true, true, true)))
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
        Assert.Equal("hotkit 1.2.0: keeping unlocked", Tray.Tip("1.2.0", ["keeping unlocked"]))
        Assert.Equal("hotkit 1.2.0: a, b", Tray.Tip("1.2.0", ["a", "b"]))
    }

    static Test_UnknownToggleThrows() {
        Assert.Throws(() => PowerModule.Set("keepWarm", true), "Unknown power toggle")
    }
}
TestRunner.Add(Power_Tests)
