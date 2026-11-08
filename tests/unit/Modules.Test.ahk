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

    ; Front-to-back stack for ZOrderInsertAfter. Spec: "hwnd[:flags]" where
    ; flags hold "t" (topmost) and/or "n" (not a peer); every window overlaps
    ; the 0..100 square unless its spec is "hwnd:far".
    static ZStack(specs*) {
        out := []
        for spec in specs {
            parts := StrSplit(spec, ":")
            flags := parts.Length > 1 ? parts[2] : ""
            far := flags = "far"
            out.Push({ hwnd: Integer(parts[1]), topmost: !far && InStr(flags, "t") > 0,
                peer: far || !InStr(flags, "n"),
                rect: far ? { left: 500, top: 0, right: 600, bottom: 100 } : { left: 0, top: 0, right: 100, bottom: 100 } })
        }
        return out
    }

    static Test_ZOrderBackwardSkipsNonPeersAndFarWindows() {
        z := (s*) => Modules_Tests.ZStack(s*)
        Assert.Equal(3, WindowUtil.ZOrderInsertAfter(z("1", "2:n", "3", "4"), 1, "backward"))
        Assert.Equal(4, WindowUtil.ZOrderInsertAfter(z("1", "2:far", "4"), 1, "backward"))
        Assert.Equal(3, WindowUtil.ZOrderInsertAfter(z("2", "1", "3"), 2, "Backward"))
        Assert.Equal("", WindowUtil.ZOrderInsertAfter(z("1", "2:far", "3:n"), 1, "backward"))
    }

    static Test_ZOrderBackwardOverlapIsStrict() {
        z := Modules_Tests.ZStack("1", "2")
        for edge in [{ left: 100, top: 0, right: 200, bottom: 100 }, { left: -100, top: 0, right: 0, bottom: 100 },
            { left: 0, top: 100, right: 100, bottom: 200 }, { left: 0, top: -100, right: 100, bottom: 0 }] {
            z[2].rect := edge
            Assert.Equal("", WindowUtil.ZOrderInsertAfter(z, 1, "backward"), "touching edges do not overlap")
        }
        z[2].rect := { left: 99, top: 99, right: 200, bottom: 200 }
        Assert.Equal(2, WindowUtil.ZOrderInsertAfter(z, 1, "backward"))
    }

    static Test_ZOrderToBackUsesLastPeerInBand() {
        z := (s*) => Modules_Tests.ZStack(s*)
        Assert.Equal(4, WindowUtil.ZOrderInsertAfter(z("1", "2", "3:far", "4", "5:n"), 1, "back"))
        Assert.Equal(3, WindowUtil.ZOrderInsertAfter(z("1:t", "2:t", "3:t", "4", "5"), 1, "back"), "topmost stays topmost")
        Assert.Equal("", WindowUtil.ZOrderInsertAfter(z("2", "1", "3:n"), 2, "back"))
        Assert.Equal("", WindowUtil.ZOrderInsertAfter(z("1:t", "2", "3"), 1, "back"))
    }

    static Test_ZOrderForwardInsertsAboveNextOverlap() {
        z := (s*) => Modules_Tests.ZStack(s*)
        Assert.Equal(2, WindowUtil.ZOrderInsertAfter(z("2", "3", "4:far", "1"), 4, "forward"))
        Assert.Equal(0, WindowUtil.ZOrderInsertAfter(z("3", "2:n", "1"), 3, "forward"), "first window: HWND_TOP")
        Assert.Equal(0, WindowUtil.ZOrderInsertAfter(z("9:t", "3", "1"), 3, "forward"), "never above topmost")
        Assert.Equal(9, WindowUtil.ZOrderInsertAfter(z("9:t", "3:t", "1:t"), 3, "forward"))
        Assert.Equal("", WindowUtil.ZOrderInsertAfter(z("9:t", "2:far", "1"), 3, "forward"))
    }

    static Test_ZOrderToFront() {
        z := (s*) => Modules_Tests.ZStack(s*)
        Assert.Equal(0, WindowUtil.ZOrderInsertAfter(z("2:far", "1"), 2, "front"))
        Assert.Equal("", WindowUtil.ZOrderInsertAfter(z("9:t", "2:n", "1"), 3, "front"))
        Assert.Equal("", WindowUtil.ZOrderInsertAfter(z("1", "2"), 1, "front"))
        Assert.Throws(() => WindowUtil.ZOrderInsertAfter(z("1"), 1, "sideways"), "Unknown z-order direction")
    }

    static Test_ZOrderAnchorsFallBackInDirectionOfTravel() {
        z := (s*) => Modules_Tests.ZStack(s*)
        Assert.Equal("3,4,5,1", Modules_Tests.Join(WindowUtil.ZOrderAnchors(z("1", "2:far", "3", "4:n", "5"), 1, "backward")))
        Assert.Equal("5,1", Modules_Tests.Join(WindowUtil.ZOrderAnchors(z("1", "3", "5"), 1, "back")))
        Assert.Equal("3,4", Modules_Tests.Join(WindowUtil.ZOrderAnchors(z("1:t", "3:t", "4:t", "5"), 1, "backward")), "topmost: no HWND_BOTTOM")
        Assert.Equal("7,9,0", Modules_Tests.Join(WindowUtil.ZOrderAnchors(z("8:t", "9", "7", "3", "1"), 5, "forward")))
        Assert.Equal("0", Modules_Tests.Join(WindowUtil.ZOrderAnchors(z("3", "1"), 2, "front")))
        Assert.Equal(0, WindowUtil.ZOrderAnchors(z("1", "2"), 1, "front").Length)
    }

    static Test_CycleIndexWraps() {
        Assert.Equal(2, WindowUtil.CycleIndex(3, 1, "next"))
        Assert.Equal(1, WindowUtil.CycleIndex(3, 3, "Next"), "wraps forward")
        Assert.Equal(1, WindowUtil.CycleIndex(3, 0, "next"), "nothing selected: first")
        Assert.Equal(2, WindowUtil.CycleIndex(3, 3, "previous"))
        Assert.Equal(3, WindowUtil.CycleIndex(3, 1, "previous"), "wraps back")
        Assert.Equal(3, WindowUtil.CycleIndex(3, 0, "previous"), "nothing selected: last")
        Assert.Equal(0, WindowUtil.CycleIndex(0, 0, "next"))
        Assert.Equal(0, WindowUtil.CycleIndex(0, 0, "previous"))
        Assert.Throws(() => WindowUtil.CycleIndex(1, 1, "sideways"), "Unknown cycle direction")
    }

    static Test_CycleRestoreAnchorsNearestAboveFirst() {
        Assert.Equal("12,11,0", Modules_Tests.Join(WindowUtil.CycleRestoreAnchors([11, 12, 13], 3)))
        Assert.Equal("0", Modules_Tests.Join(WindowUtil.CycleRestoreAnchors([11, 12, 13], 1)))
    }

    static Test_CycleHoldKeysFromLayerBindingsOnHotkey() {
        layers := Map()
        layers.CaseSense := "Off"
        layers["caps"] := { key: "CapsLock" }
        specs := [
            { keys: "[", action: "window.cycleNext", layer: "caps" },
            { keys: "]", action: "window.cyclePrevious", layer: "caps" },
            { keys: "[", action: "window.cycleNext", layer: "" },
            { keys: "[", action: "window.sendBackward", layer: "caps" },
            { keys: "[", gestures: 1, layer: "caps" }
        ]
        Assert.Equal("CapsLock", Modules_Tests.Join(WindowsModule.CycleHoldKeys(specs, layers, "[")))
        Assert.Equal("CapsLock", Modules_Tests.Join(WindowsModule.CycleHoldKeys(specs, layers, "]")))
        Assert.Equal("", Modules_Tests.Join(WindowsModule.CycleHoldKeys(specs, layers, "F7")))
    }

    static Join(arr) {
        out := ""
        for v in arr
            out .= (A_Index > 1 ? "," : "") v
        return out
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

    static Test_DesktopHostPrefersIconView() {
        progman := { hwnd: 1, cls: "Progman", hasDefView: false }
        worker := { hwnd: 2, cls: "WorkerW", hasDefView: true }
        bare := { hwnd: 3, cls: "WorkerW", hasDefView: false }
        Assert.Equal(2, DesktopModule.PickDesktopHost([progman, bare, worker]))
        Assert.Equal(1, DesktopModule.PickDesktopHost([{ hwnd: 1, cls: "Progman", hasDefView: true }, worker]))
        Assert.Equal(1, DesktopModule.PickDesktopHost([bare, progman]))
        Assert.Equal(0, DesktopModule.PickDesktopHost([bare]))
        Assert.Equal(0, DesktopModule.PickDesktopHost([]))
    }

    static Test_TaskbarDigit() {
        Assert.Equal("1", DesktopModule.TaskbarDigit(1))
        Assert.Equal("9", DesktopModule.TaskbarDigit("9"))
        Assert.Equal("0", DesktopModule.TaskbarDigit(10))
        Assert.Equal("0", DesktopModule.TaskbarDigit(0))
        Assert.Throws(() => DesktopModule.TaskbarDigit(11), "Taskbar slot")
        Assert.Throws(() => DesktopModule.TaskbarDigit(-1), "Taskbar slot")
        Assert.Throws(() => DesktopModule.TaskbarDigit("x"), "Taskbar slot")
    }

    static Test_TaskbarHoldKeys() {
        down := Map()
        down.CaseSense := "Off"
        down["CapsLock"] := true, down["Shift"] := true
        isDown := (k) => down.Has(k)
        held := DesktopModule.TaskbarHoldKeys(["CapsLock", "capslock", "", "Ctrl", "Shift"], isDown)
        Assert.Equal(2, held.Length)
        Assert.Equal("CapsLock", held[1])
        Assert.Equal("Shift", held[2])
        Assert.Equal(0, DesktopModule.TaskbarHoldKeys(["Ctrl", "Alt"], isDown).Length)
        Assert.Equal(0, DesktopModule.TaskbarHoldKeys([], isDown).Length)
    }

    static Test_TaskbarTriggerKeysUseTheBindingsLayer() {
        layers := Map("caps", { key: "CapsLock" }, "tab", { key: "Tab" })
        specs := [
            { keys: "1", action: "taskbar.activate", layer: "caps" },
            { keys: "1", action: "app.toggle", layer: "tab" },
            { keys: "2", action: "taskbar.activate", layer: "tab" },
            { keys: "F1", action: "taskbar.activate", layer: "" },
            { keys: "1", kind: "gestures", layer: "tab" },
        ]
        keys := DesktopModule.TaskbarTriggerKeys(specs, layers, "1")
        Assert.Equal(1, keys.Length)
        Assert.Equal("CapsLock", keys[1])
        Assert.Equal(0, DesktopModule.TaskbarTriggerKeys(specs, layers, "F1").Length)
        Assert.Equal(0, DesktopModule.TaskbarTriggerKeys(specs, layers, "3").Length)
    }

    static Test_TaskbarRepeatKey() {
        Assert.Equal("1", DesktopModule.TaskbarRepeatKey("1"))
        Assert.Equal("N", DesktopModule.TaskbarRepeatKey("<^+N"))
        Assert.Equal("F13", DesktopModule.TaskbarRepeatKey("~*$F13"))
        Assert.Equal("", DesktopModule.TaskbarRepeatKey("LShift & Volume_Up"))
        Assert.Equal("", DesktopModule.TaskbarRepeatKey("1 Up"))
        Assert.Equal("", DesktopModule.TaskbarRepeatKey(""))
    }

    static Test_FullScreenDetection() {
        mon := { left: 0, top: 0, right: 1920, bottom: 1080 }
        full := { left: 0, top: 0, right: 1920, bottom: 1080 }
        maxed := { left: -8, top: -8, right: 1928, bottom: 1088 }
        work := { left: -8, top: -8, right: 1928, bottom: 1048 }
        popup := 0x80000000, caption := 0xC00000
        Assert.True(DesktopModule.IsFullScreen("TscShellContainerClass", popup, full, mon))
        Assert.True(DesktopModule.IsFullScreen("X", 0x800000, maxed, mon)) ; border only, not a caption
        Assert.False(DesktopModule.IsFullScreen("X", caption, maxed, mon))
        Assert.False(DesktopModule.IsFullScreen("X", popup, work, mon))
        Assert.False(DesktopModule.IsFullScreen("X", popup, { left: 1, top: 0, right: 1920, bottom: 1080 }, mon))
        Assert.False(DesktopModule.IsFullScreen("X", popup, { left: 0, top: 1, right: 1920, bottom: 1080 }, mon))
        Assert.False(DesktopModule.IsFullScreen("X", popup, { left: 0, top: 0, right: 1919, bottom: 1080 }, mon))
        Assert.False(DesktopModule.IsFullScreen("Progman", popup, full, mon))
        Assert.False(DesktopModule.IsFullScreen("WorkerW", popup, full, mon))
        Assert.False(DesktopModule.IsFullScreen("Shell_TrayWnd", popup, full, mon))
        Assert.False(DesktopModule.IsFullScreen("Shell_SecondaryTrayWnd", popup, full, mon))
        second := { left: 1920, top: 0, right: 4480, bottom: 1440 }
        Assert.True(DesktopModule.IsFullScreen("X", popup, second, second))
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

    static Test_ActivationListenersRunEvenWhilePaused() {
        saved := FocusHistory._listeners, savedSeq := FocusHistory.Seq
        try {
            seen := []
            FocusHistory._listeners := [(hwnd) => seen.Push(hwnd)]
            FocusHistory.Seq := Map()
            FocusHistory._OnShell(1, 500)  ; HSHELL_WINDOWCREATED: ignored
            FocusHistory._OnShell(4, 501)
            FocusHistory.Pause(60000)
            FocusHistory._OnShell(0x8004, 502)
            Assert.Equal([501, 502], seen)
            Assert.True(FocusHistory.Seq.Has(501))
            Assert.False(FocusHistory.Seq.Has(502), "paused activations are not recorded as focus")
        } finally {
            FocusHistory._listeners := saved, FocusHistory.Seq := savedSeq
            FocusHistory._ignoreUntil := 0
        }
    }
}
TestRunner.Add(Modules_Tests)
