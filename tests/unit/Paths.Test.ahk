#Requires AutoHotkey v2.0

class Paths_Tests {
    static Setup() {
        Paths.Override := ""
        EnvSet("HOTKIT_CONFIG_DIR")
        EnvSet("XDG_CONFIG_HOME")
    }

    static Teardown() => Paths_Tests.Setup()

    static Test_SyncCopyWritesOnlyWhenDifferent() {
        dir := A_Temp "\hotkit-synccopy-" A_TickCount
        DirCreate(dir)
        try {
            FileAppend('{ "a": 1 }', dir "\src.json", "UTF-8")
            Assert.True(Paths.SyncCopy(dir "\src.json", dir "\dst.json"), "missing target is written")
            Assert.False(Paths.SyncCopy(dir "\src.json", dir "\dst.json"), "identical target is left alone")
            FileDelete(dir "\src.json")
            FileAppend('{ "a": 2 }', dir "\src.json", "UTF-8")
            Assert.True(Paths.SyncCopy(dir "\src.json", dir "\dst.json"), "a changed schema replaces the copy")
            Assert.Equal(FileRead(dir "\src.json", "UTF-8"), FileRead(dir "\dst.json", "UTF-8"))
            Assert.True(FileExist(Paths.Schema()) != "", "the bundled schema exists")
            Assert.True(Paths.IsHotkitSchema(Paths.Schema()))
            Assert.False(Paths.IsHotkitSchema(dir "\src.json"), "another file is not ours")
            Assert.False(Paths.IsHotkitSchema(dir "\missing.json"))
            FileAppend('{ "title": "mine", "$defs": { "hk": { "title": "hotkit configuration" } } }', dir "\nested.json", "UTF-8")
            Assert.False(Paths.IsHotkitSchema(dir "\nested.json"), "a schema embedding ours is not a managed copy")
        } finally {
            DirDelete(dir, true)
        }
    }

    static Test_DefaultConfigDir() {
        Assert.Equal(EnvGet("USERPROFILE") "\.config\hotkit", Paths.ConfigDir())
        file := Paths.ConfigFile()
        Assert.True(file = Paths.ConfigDir() "\config.jsonc" || file = Paths.ConfigDir() "\config.json", file)
        Assert.Equal(Paths.ConfigDir() "\plugins", Paths.PluginDir())
    }

    static Test_ConfigFilePrefersJsoncAndKeepsAnExistingJson() {
        dir := A_Temp "\hotkit-configfile-" A_TickCount
        DirCreate(dir)
        try {
            Paths.Override := dir
            Assert.Equal(dir "\config.jsonc", Paths.ConfigFile(), "a new config is config.jsonc")
            FileAppend("{}", dir "\config.json", "UTF-8")
            Assert.Equal(dir "\config.json", Paths.ConfigFile(), "an existing config.json is still used")
            FileAppend("{}", dir "\config.jsonc", "UTF-8")
            Assert.Equal(dir "\config.jsonc", Paths.ConfigFile(), "config.jsonc wins when both exist")
        } finally {
            DirDelete(dir, true)
        }
    }

    static Test_XdgThenEnvThenOverride() {
        EnvSet("XDG_CONFIG_HOME", "C:\xdg")
        Assert.Equal("C:\xdg\hotkit", Paths.ConfigDir())
        EnvSet("HOTKIT_CONFIG_DIR", "D:\cfg")
        Assert.Equal("D:\cfg", Paths.ConfigDir())
        Paths.Override := "E:\over\.\x\.."
        Assert.Equal("E:\over", Paths.ConfigDir())
    }

    static Test_LogFileIsMachineLocalUnlessOverridden() {
        original := EnvGet("LOCALAPPDATA")
        try {
            EnvSet("HOTKIT_CONFIG_DIR", "D:\cfg")
            EnvSet("LOCALAPPDATA", "C:\local")
            Assert.Equal("C:\local\hotkit\hotkit.log", Paths.LogFile())
            EnvSet("LOCALAPPDATA", "")
            Assert.Equal("D:\cfg\hotkit.log", Paths.LogFile(), "falls back to the config dir")
            EnvSet("LOCALAPPDATA", "C:\local")
            Paths.Override := "E:\over"
            Assert.Equal("E:\over\hotkit.log", Paths.LogFile(), "--config-dir keeps the log beside that config")
        } finally {
            EnvSet("LOCALAPPDATA", original)
        }
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
