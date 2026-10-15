#Requires AutoHotkey v2.0

class WindowMatcher_Tests {
    static Info(overrides := unset) {
        info := { exe: "app.exe", class: "Chrome_WidgetWin_1", title: "Hello", style: 0x10000000,
            owner: 0, minimized: false, width: 800, height: 600, aumid: "App.Id" }
        if IsSet(overrides) {
            for k, v in overrides.OwnProps()
                info.%k% := v
        }
        return info
    }

    static Test_EmptySpecMatchesAnything() {
        Assert.True(WindowMatcher.Matches(Map(), WindowMatcher_Tests.Info()))
    }

    static Test_ExeIsCaseInsensitive() {
        Assert.True(WindowMatcher.Matches(Map("exe", "APP.EXE"), WindowMatcher_Tests.Info()))
        Assert.False(WindowMatcher.Matches(Map("exe", "other.exe"), WindowMatcher_Tests.Info()))
    }

    static Test_ClassIsExact() {
        Assert.True(WindowMatcher.Matches(Map("class", "Chrome_WidgetWin_1"), WindowMatcher_Tests.Info()))
        Assert.False(WindowMatcher.Matches(Map("class", "chrome_widgetwin_1"), WindowMatcher_Tests.Info()))
    }

    static Test_TitleRegexAndNotEmpty() {
        Assert.True(WindowMatcher.Matches(Map("title", "^Hel"), WindowMatcher_Tests.Info()))
        Assert.False(WindowMatcher.Matches(Map("title", "^x"), WindowMatcher_Tests.Info()))
        Assert.False(WindowMatcher.Matches(Map("titleNotEmpty", true), WindowMatcher_Tests.Info({ title: "" })))
        Assert.True(WindowMatcher.Matches(Map("titleNotEmpty", false), WindowMatcher_Tests.Info({ title: "" })))
    }

    static Test_VisibleAndTopLevel() {
        Assert.False(WindowMatcher.Matches(Map("visible", true), WindowMatcher_Tests.Info({ style: 0 })))
        Assert.False(WindowMatcher.Matches(Map("topLevel", true), WindowMatcher_Tests.Info({ owner: 1234 })))
        Assert.True(WindowMatcher.Matches(Map("visible", true, "topLevel", true), WindowMatcher_Tests.Info()))
    }

    static Test_MinimumSizeIgnoredWhenMinimized() {
        spec := Map("minWidth", 300, "minHeight", 200)
        Assert.False(WindowMatcher.Matches(spec, WindowMatcher_Tests.Info({ width: 100 })))
        Assert.False(WindowMatcher.Matches(spec, WindowMatcher_Tests.Info({ height: 199 })))
        Assert.True(WindowMatcher.Matches(spec, WindowMatcher_Tests.Info({ width: 300, height: 200 })))
        Assert.True(WindowMatcher.Matches(spec, WindowMatcher_Tests.Info({ width: 0, minimized: true })))
    }

    static Test_AppUserModelId() {
        Assert.True(WindowMatcher.Matches(Map("appUserModelId", "App.Id"), WindowMatcher_Tests.Info()))
        Assert.False(WindowMatcher.Matches(Map("appUserModelId", "Other"), WindowMatcher_Tests.Info()))
    }

    static Test_ValidateRejectsUnknownFields() {
        Assert.Throws(() => WindowMatcher.Validate(Map("colour", "x")), "Unknown window match field")
        Assert.Throws(() => WindowMatcher.Validate("x"), "must be an object")
        Assert.True(WindowMatcher.Predicate(Map("exe", "x.exe")) is Func)
    }

    static Test_VisibilityAndOwnershipIgnoredUnlessRequested() {
        hidden := WindowMatcher_Tests.Info({ style: 0, owner: 0x1234, title: "" })
        Assert.True(WindowMatcher.Matches(Map(), hidden))
        Assert.True(WindowMatcher.Matches(Map("visible", false, "topLevel", false), hidden))
    }

    static Test_ValidateReturnsSpec() {
        spec := Map("exe", "a.exe")
        Assert.True(WindowMatcher.Validate(spec) == spec)
    }
}
TestRunner.Add(WindowMatcher_Tests)
