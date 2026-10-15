#Requires AutoHotkey v2.0

class Modules_Tests {
    static Test_SwitchableSkipsToolWindows() {
        Assert.False(WindowsModule.IsSwitchable({ exStyle: 0x80, exe: "a.exe", title: "x" }, []))
        Assert.True(WindowsModule.IsSwitchable({ exStyle: 0, exe: "a.exe", title: "x" }, []))
    }

    static Test_SwitchableIgnoreRules() {
        ignore := [Map("exe", "wrapper.exe", "emptyTitle", true), Map("title", "^Hidden")]
        Assert.False(WindowsModule.IsSwitchable({ exStyle: 0, exe: "WRAPPER.EXE", title: "" }, ignore))
        Assert.True(WindowsModule.IsSwitchable({ exStyle: 0, exe: "wrapper.exe", title: "Session" }, ignore))
        Assert.False(WindowsModule.IsSwitchable({ exStyle: 0, exe: "x.exe", title: "Hidden thing" }, ignore))
        Assert.True(WindowsModule.IsSwitchable({ exStyle: 0, exe: "x.exe", title: "Shown" }, ignore))
    }

    static Test_QuickWindowLaunchCommand() {
        Assert.Equal('app.exe --app="u"', QuickWindowsModule.LaunchCommand("app.exe", '--app="u"'))
        Assert.Equal("app.exe --a=x --b", QuickWindowsModule.LaunchCommand("app.exe --a={mode} --b", "x"))
        Assert.Equal("app.exe", QuickWindowsModule.LaunchCommand("app.exe", ""))
        EnvSet("AHK_TEST_DIR", "C:\d")
        Assert.Equal("C:\d\app.exe", QuickWindowsModule.LaunchCommand("%AHK_TEST_DIR%\app.exe", ""))
    }

    static Test_QuickWindowRequiresExeAndLaunch() {
        QuickWindowsModule.Definitions := Map("bad", Map("exe", "x.exe"))
        QuickWindowsModule.Instances := Map()
        Assert.Throws(() => QuickWindowsModule.Get("bad"), "launch")
        Assert.Throws(() => QuickWindowsModule.Get("missing"), "Unknown quick window")
    }

    static Test_QuickWindowRejectsBadMatch() {
        QuickWindowsModule.Definitions := Map("q", Map("exe", "x.exe", "launch", "x.exe", "match", Map("nope", 1)))
        QuickWindowsModule.Instances := Map()
        Assert.Throws(() => QuickWindowsModule.Get("q"), "Unknown window match field")
    }

    static Test_AwakeModeFlips() {
        Assert.Equal(0, DesktopModule.NextAwakeMode(1))
        Assert.Equal(1, DesktopModule.NextAwakeMode(0))
        Assert.Equal(1, DesktopModule.NextAwakeMode(2))
    }

    static Test_AppsRequireDefinitions() {
        AppsModule.Apps := Map("a", Map("name", "A"))
        Assert.Throws(() => AppsModule.Get("missing"), "Unknown app")
        Assert.Throws(() => AppsModule.Get("a"), "run")
    }

    static Test_OsdFilter() {
        rows := [
            { keys: "RCtrl+PgUp", description: "Brighter", action: "brightness.increase", layer: "", group: "", source: "config" },
            { keys: "CapsLock+N", description: "Notepad", action: "app.toggle", layer: "caps", group: "", source: "config" }
        ]
        Assert.Equal(2, ShortcutOsd.FilterRows(rows, "").Length)
        Assert.Equal(1, ShortcutOsd.FilterRows(rows, "bright").Length)
        Assert.Equal(1, ShortcutOsd.FilterRows(rows, "caps note").Length)
        Assert.Equal(0, ShortcutOsd.FilterRows(rows, "caps bright").Length)
    }

    static Test_OsdFilterKeepsMatchingRows() {
        rows := [
            { keys: "F1", description: "Alpha", action: "a.one", layer: "", group: "", source: "config" },
            { keys: "F2", description: "Beta", action: "b.two", layer: "", group: "work", source: "plugin" }
        ]
        Assert.Equal("Alpha", ShortcutOsd.FilterRows(rows, "alpha")[1].description)
        Assert.Equal("Beta", ShortcutOsd.FilterRows(rows, "  work  ")[1].description)
        Assert.Equal("Beta", ShortcutOsd.FilterRows(rows, "plugin b.two")[1].description)
    }

    static Test_CycleTargetRotatesThroughWindows() {
        Assert.Equal(0, AppUtil.CycleTarget([], 1))
        Assert.Equal(11, AppUtil.CycleTarget([11, 12, 13], 99), "app not active: most recent window")
        Assert.Equal(13, AppUtil.CycleTarget([11, 12, 13], 11), "app active: bottom-most window")
        Assert.Equal(11, AppUtil.CycleTarget([11], 11), "single window stays put")
    }

    static Test_MostRecentPrefersLastFocused() {
        seq := Map(11, 5, 12, 9)
        Assert.Equal(0, FocusHistory.MostRecent([], seq))
        Assert.Equal(12, FocusHistory.MostRecent([11, 12, 13], seq), "last focused wins over z-order")
        Assert.Equal(11, FocusHistory.MostRecent([11, 13], Map()), "never focused: keep z-order")
        Assert.Equal(11, FocusHistory.MostRecent([13, 11], Map(11, 1)), "seen beats never seen")
    }

    static Test_CycleTargetUsesFocusHistoryWhenInactive() {
        Assert.Equal(13, AppUtil.CycleTarget([11, 12, 13], 99, Map(13, 7, 11, 2)))
        Assert.Equal(13, AppUtil.CycleTarget([11, 12, 13], 11, Map(12, 7)), "active app still rotates")
    }

    static Test_FocusHistoryNoteOrders() {
        saved := FocusHistory.Seq, savedCounter := FocusHistory.Counter
        try {
            FocusHistory.Seq := Map()
            FocusHistory.Note(101), FocusHistory.Note(102), FocusHistory.Note(101)
            Assert.Equal(101, FocusHistory.MostRecent([102, 101], FocusHistory.Seq))
            FocusHistory.Note(0)
            Assert.Equal(2, FocusHistory.Seq.Count, "a zero hwnd is ignored")
        } finally {
            FocusHistory.Seq := saved, FocusHistory.Counter := savedCounter
        }
    }
}
TestRunner.Add(Modules_Tests)
