#Requires AutoHotkey v2.0

class Tray_Tests {
    static Dir := ""

    static Setup() {
        Tray_Tests.Dir := A_Temp "\hotkit-tray-" A_TickCount
        DirCreate(Tray_Tests.Dir "\icons")
        FileAppend("", Tray_Tests.Dir "\icons\my.ico")
    }

    static Teardown() {
        Bindings.Reset()
        try DirDelete(Tray_Tests.Dir, true)
        EnvSet("HOTKIT_TRAY_TEST")
    }

    static Cfg(trayJson) {
        cfg := Config.FromText('{ "tray": ' trayJson ' }')
        cfg.path := Tray_Tests.Dir "\config.text"
        return cfg
    }

    static Test_DefaultIconShipsWithRepo() {
        Assert.Equal(Paths.RepoRoot() "\assets\hotkit.ico", Tray.DefaultIcon())
        Assert.True(FileExist(Tray.DefaultIcon()), "missing " Tray.DefaultIcon())
    }

    static Test_NoIconConfiguredUsesDefaultWithoutProblem() {
        for text in ['{}', '{ "icon": "" }', '{ "icon": null }'] {
            icon := Tray.ResolveIcon(Tray_Tests.Cfg(text))
            Assert.Equal(Tray.DefaultIcon(), icon.file, text)
            Assert.Equal(1, icon.index, text)
            Assert.False(icon.custom, text)
            Assert.Equal("", icon.problem, text)
        }
    }

    static Test_RelativePathResolvesNextToConfig() {
        icon := Tray.ResolveIcon(Tray_Tests.Cfg('{ "icon": "icons/my.ico" }'))
        Assert.Equal(Tray_Tests.Dir "\icons\my.ico", icon.file)
        Assert.Equal(1, icon.index)
        Assert.True(icon.custom)
        Assert.Equal("", icon.problem)
    }

    static Test_AbsolutePathAndEnvironmentVariables() {
        EnvSet("HOTKIT_TRAY_TEST", Tray_Tests.Dir)
        icon := Tray.ResolveIcon(Tray_Tests.Cfg('{ "icon": "%HOTKIT_TRAY_TEST%\\icons\\.\\my.ico" }'))
        Assert.Equal(Tray_Tests.Dir "\icons\my.ico", icon.file)
        Assert.True(icon.custom)
    }

    static Test_ObjectFormWithIndex() {
        icon := Tray.ResolveIcon(Tray_Tests.Cfg('{ "icon": { "file": "icons\\my.ico", "index": -3 } }'))
        Assert.Equal(Tray_Tests.Dir "\icons\my.ico", icon.file)
        Assert.Equal(-3, icon.index)
        Assert.True(icon.custom)
        icon := Tray.ResolveIcon(Tray_Tests.Cfg('{ "icon": { "file": "icons\\my.ico" } }'))
        Assert.Equal(1, icon.index, "index defaults to 1")
    }

    static Test_BareNameFallsBackToSystem32() {
        Assert.Equal(Paths.Normalize(A_WinDir "\System32\shell32.dll"), Tray.FindIconFile("shell32.dll", Tray_Tests.Dir "\config.text"))
        Assert.Equal("", Tray.FindIconFile("sub\shell32.dll", Tray_Tests.Dir "\config.text"), "only bare names search System32")
    }

    static Test_ConfigDirWinsOverSystem32() {
        FileAppend("", Tray_Tests.Dir "\shell32.dll")
        Assert.Equal(Tray_Tests.Dir "\shell32.dll", Tray.FindIconFile("shell32.dll", Tray_Tests.Dir "\config.text"))
    }

    static Test_MissingFileFallsBackWithProblem() {
        icon := Tray.ResolveIcon(Tray_Tests.Cfg('{ "icon": "icons/nope.ico" }'))
        Assert.Equal(Tray.DefaultIcon(), icon.file)
        Assert.False(icon.custom)
        Assert.Contains(icon.problem, "file not found: icons/nope.ico")
        Assert.Contains(icon.problem, "using the default icon")
    }

    static Test_DirectoryIsNotAnIcon() {
        icon := Tray.ResolveIcon(Tray_Tests.Cfg('{ "icon": "icons" }'))
        Assert.False(icon.custom)
        Assert.Contains(icon.problem, "file not found")
    }

    static Test_BadObjectFormsFallBackWithProblem() {
        cases := Map(
            '{ "icon": { "index": 2 } }', "missing 'file'",
            '{ "icon": { "file": ["x"] } }', "missing 'file'",
            '{ "icon": { "file": "icons/my.ico", "index": 0 } }', "non-zero whole number",
            '{ "icon": { "file": "icons/my.ico", "index": 1.5 } }', "non-zero whole number",
            '{ "icon": { "file": "icons/my.ico", "index": "two" } }', "non-zero whole number")
        for text, fragment in cases {
            icon := Tray.ResolveIcon(Tray_Tests.Cfg(text))
            Assert.False(icon.custom, text)
            Assert.Equal(Tray.DefaultIcon(), icon.file, text)
            Assert.Contains(icon.problem, fragment)
        }
    }

    static Test_ApplyIconLoadsCustomIcon() {
        FileCopy(Tray.DefaultIcon(), Tray_Tests.Dir "\icons\copy.ico")
        Bindings.Reset()
        icon := Tray.ApplyIcon(Tray_Tests.Cfg('{ "icon": "icons/copy.ico" }'))
        Assert.True(icon.custom)
        Assert.Equal(Tray_Tests.Dir "\icons\copy.ico", A_IconFile)
        Assert.Equal(0, Bindings.problems.Length)
    }

    static Test_ApplyIconFallsBackWhenIconWontLoad() {
        Bindings.Reset()
        Tray.ApplyIcon(Tray_Tests.Cfg('{ "icon": "icons/my.ico" }'))
        Assert.Equal(1, Bindings.problems.Length)
        Assert.Contains(Bindings.problems[1], "could not load icon 1 from " Tray_Tests.Dir "\icons\my.ico")
        Assert.Equal(Tray.DefaultIcon(), A_IconFile)
    }

    static Test_ConfigWithoutPathUsesConfigDir() {
        cfg := Config.FromText('{ "tray": { "icon": "icons/my.ico" } }')
        saved := Paths.Override
        try {
            Paths.Override := Tray_Tests.Dir
            Assert.Equal(Tray_Tests.Dir "\icons\my.ico", Tray.ResolveIcon(cfg).file)
        } finally {
            Paths.Override := saved
        }
    }
    static Test_BadgeSitsInLowerRightCorner() {
        Assert.Equal("", Tray.BadgePixel(0, 0, 16), "top-left shows the icon")
        Assert.Equal("", Tray.BadgePixel(15, 0, 16), "top-right shows the icon")
        Assert.Equal("", Tray.BadgePixel(0, 15, 16), "bottom-left shows the icon")
        Assert.NotEqual("", Tray.BadgePixel(12, 12, 16))
    }

    static Test_BadgeHasRingFillAndMark() {
        for size in [16, 20, 24, 32, 64] {
            seen := Map("ring", 0, "fill", 0, "mark", 0)
            loop size {
                y := A_Index - 1
                loop size {
                    kind := Tray.BadgePixel(A_Index - 1, y, size)
                    if (kind != "")
                        seen[kind] += 1
                }
            }
            for kind, n in seen
                Assert.True(n > 0, kind " at " size "px")
            Assert.True(seen["fill"] > seen["mark"], "mostly amber at " size "px")
        }
    }

    static Test_BadgedIconFromDefaultIcon() {
        h := Tray.BadgedIcon(Tray.DefaultIcon(), 1, 16)
        Assert.True(h != 0)
        DllCall("DestroyIcon", "Ptr", h)
        Assert.Equal(0, Tray.BadgedIcon(Tray_Tests.Dir "\icons\my.ico", 1, 16), "unloadable icon")
    }
}
TestRunner.Add(Tray_Tests)
