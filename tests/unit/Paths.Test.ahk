#Requires AutoHotkey v2.0

class Paths_Tests {
    static Setup() {
        Paths.Override := ""
        EnvSet("HOTKIT_CONFIG_DIR")
        EnvSet("XDG_CONFIG_HOME")
    }

    static Teardown() => Paths_Tests.Setup()

    static Test_DefaultConfigDir() {
        Assert.Equal(EnvGet("USERPROFILE") "\.config\hotkit", Paths.ConfigDir())
        Assert.Equal(Paths.ConfigDir() "\config.json", Paths.ConfigFile())
        Assert.Equal(Paths.ConfigDir() "\plugins", Paths.PluginDir())
    }

    static Test_XdgThenEnvThenOverride() {
        EnvSet("XDG_CONFIG_HOME", "C:\xdg")
        Assert.Equal("C:\xdg\hotkit", Paths.ConfigDir())
        EnvSet("HOTKIT_CONFIG_DIR", "D:\cfg")
        Assert.Equal("D:\cfg", Paths.ConfigDir())
        Paths.Override := "E:\over\.\x\.."
        Assert.Equal("E:\over", Paths.ConfigDir())
    }

    static Test_ExpandEnvironmentAndTilde() {
        EnvSet("AHK_TEST_VAR", "value")
        Assert.Equal("a\value\b", Paths.Expand("a\%AHK_TEST_VAR%\b"))
        Assert.Equal(EnvGet("USERPROFILE") "\x", Paths.Expand("~\x"))
        Assert.Equal("100%", Paths.Expand("100%"))
        Assert.Equal("a\\b", Paths.Expand("a\%AHK_UNSET_VAR_XYZ%\b"))
    }

    static Test_NormalizeSegments() {
        Assert.Equal("C:\a\c", Paths.Normalize("C:/a/b/../c/./"))
        Assert.Equal("\\server\share\x", Paths.Normalize("\\server\share\y\..\x"))
    }

    static Test_RepoLayout() {
        Assert.True(FileExist(Paths.ExampleConfig()), "example config should exist at " Paths.ExampleConfig())
        Assert.Equal(Paths.RepoRoot() "\local\plugins.generated.ahk", Paths.PluginStub())
    }

    static Test_ExpandBareTildeAndForwardSlash() {
        Assert.Equal(EnvGet("USERPROFILE"), Paths.Expand("~"))
        Assert.Equal(EnvGet("USERPROFILE") "/x", Paths.Expand("~/x"))
        Assert.Equal("a~b", Paths.Expand("a~b"))
    }

    static Test_NormalizeKeepsLeadingParentSegments() {
        Assert.Equal("..\..\a", Paths.Normalize("..\..\a"))
        Assert.Equal("..\b", Paths.Normalize("a\..\..\b"))
    }
}
TestRunner.Add(Paths_Tests)
