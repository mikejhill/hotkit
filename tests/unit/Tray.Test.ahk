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
    static Test_BadgeSitsInTopRightCorner() {
        for size in [16, 20, 24, 32, 64] {
            Assert.Equal("", Tray.BadgePixel(0, 0, size), "top-left at " size "px")
            Assert.Equal("", Tray.BadgePixel(size - 1, 0, size), "outside circle at " size "px")
            Assert.NotEqual("", Tray.BadgePixel(Floor(size * 0.75), Floor(size * 0.25), size), "top-right badge at " size "px")
            loop size {
                x := A_Index - 1
                loop size - Ceil(size * 0.56) {
                    y := Ceil(size * 0.56) + A_Index - 1
                    Assert.Equal("", Tray.BadgePixel(x, y, size), "lower icon stays visible at " size "px: " x "," y)
                }
            }
        }
    }

    static Test_BadgeHasSeparateStemAndDot() {
        ; size, mark column, stem row, gap row, dot row: native pixel samples.
        for sample in [[16, 11, 3, 5, 6], [20, 14, 4, 6, 7], [24, 17, 5, 8, 9], [32, 23, 6, 11, 12]] {
            size := sample[1], x := sample[2]
            Assert.Equal("ring", Tray.BadgePixel(x, 0, size), "top outline at " size "px")
            Assert.Equal("mark", Tray.BadgePixel(x, sample[3], size), "stem at " size "px")
            Assert.Equal("fill", Tray.BadgePixel(x, sample[4], size), "gap above dot at " size "px")
            Assert.Equal("mark", Tray.BadgePixel(x, sample[5], size), "dot at " size "px")
        }
        Assert.Equal("ring", Tray.BadgePixel(7, 4, 16), "outline between badge and bolt")
        Assert.Equal("fill", Tray.BadgePixel(10, 3, 16), "fill beside stem")
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
            Assert.True(seen["fill"] > seen["mark"], "mostly coral at " size "px")
        }
    }

    static Test_BadgedIconFromDefaultIcon() {
        h := Tray.BadgedIcon(Tray.DefaultIcon(), 1, 16)
        Assert.True(h != 0)
        try {
            Assert.Equal("0xFF30475E", Tray_Tests.Render(h, 7, 4), "dark outline separates badge from bolt")
            Assert.Equal("0xFFD9735B", Tray_Tests.Render(h, 10, 3), "muted coral fill")
            Assert.Equal("0xFFFFF4E8", Tray_Tests.Render(h, 11, 3), "near-white stem")
            Assert.Equal("0xFFFFF4E8", Tray_Tests.Render(h, 11, 6), "near-white dot")
        } finally {
            DllCall("DestroyIcon", "Ptr", h)
        }
        Assert.Equal(0, Tray.BadgedIcon(Tray_Tests.Dir "\icons\my.ico", 1, 16), "unloadable icon")
    }
    ; Draws an icon onto opaque black and returns pixel (x, y) as 0xAARRGGBB.
    static Render(h, x, y) {
        bi := Buffer(40, 0)
        NumPut("UInt", 40, "Int", 16, "Int", -16, "UShort", 1, "UShort", 32, bi)
        hdc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        hbm := DllCall("CreateDIBSection", "Ptr", hdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
        old := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbm, "Ptr")
        loop 256
            NumPut("UInt", 0xFF000000, bits, (A_Index - 1) * 4)
        DllCall("DrawIconEx", "Ptr", hdc, "Int", 0, "Int", 0, "Ptr", h, "Int", 16, "Int", 16, "UInt", 0, "Ptr", 0, "UInt", 3)
        DllCall("GdiFlush")
        px := NumGet(bits, (y * 16 + x) * 4, "UInt")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
        DllCall("DeleteObject", "Ptr", hbm)
        DllCall("DeleteDC", "Ptr", hdc)
        return Format("0x{:08X}", px)
    }

    static Test_BadgeKeepsSemiTransparentPixels() {
        f := A_LineFile "\..\fixtures\semi-transparent.ico"
        plain := LoadPicture(f, "Icon1 w16 h16", &imageType)
        badged := Tray.BadgedIcon(f, 1, 16)
        Assert.Equal(Tray_Tests.Render(plain, 0, 0), Tray_Tests.Render(badged, 0, 0), "renders like the original")
        DllCall("DestroyIcon", "Ptr", plain), DllCall("DestroyIcon", "Ptr", badged)
    }

    static Test_BadgeKeepsMaskOnlyTransparency() {
        f := A_LineFile "\..\fixtures\mask-only.ico"
        badged := Tray.BadgedIcon(f, 1, 16)
        Assert.Equal("0xFF000000", Tray_Tests.Render(badged, 1, 0), "transparent column stays transparent")
        Assert.Equal("0xFFFF0000", Tray_Tests.Render(badged, 8, 0), "opaque red stays red")
        DllCall("DestroyIcon", "Ptr", badged)
    }
}
TestRunner.Add(Tray_Tests)
