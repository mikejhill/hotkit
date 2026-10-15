#Requires AutoHotkey v2.0

class Config_Tests {
    static Test_ParsesCommentsAndTrailingCommas() {
        cfg := Config.FromText('// header`n{ "a": { "b": [1, 2, ], }, /* c */ "d": "x" }')
        Assert.Equal([1, 2], cfg.Get("a.b"))
        Assert.Equal("x", cfg.Get("d"))
    }

    static Test_NormalizesLiterals() {
        cfg := Config.FromText('{ "t": true, "f": false, "n": null, "nested": [true, {"x": false}] }')
        Assert.Equal(1, cfg.Get("t"))
        Assert.Equal(0, cfg.Get("f"))
        Assert.Equal("", cfg.Get("n"))
        Assert.Equal(1, cfg.Get("nested")[1])
        Assert.Equal(0, cfg.Get("nested")[2]["x"])
    }

    static Test_DefaultsForMissingPaths() {
        cfg := Config.FromText('{ "a": { "b": 1 } }')
        Assert.Equal("dflt", cfg.Get("a.c", "dflt"))
        Assert.Equal("dflt", cfg.Get("a.b.c", "dflt"))
        Assert.Equal(0, cfg.Section("missing").Count)
        Assert.Equal(0, cfg.List("a").Length)
    }

    static Test_HasDistinguishesEmptyValues() {
        cfg := Config.FromText('{ "empty": "", "zero": 0 }')
        Assert.True(cfg.Has("empty"))
        Assert.True(cfg.Has("zero"))
        Assert.False(cfg.Has("other"))
    }

    static Test_KeysAreCaseInsensitive() {
        cfg := Config.FromText('{ "Modules": { "DisplayScale": { "debounceMs": 7 } } }')
        Assert.Equal(7, cfg.Get("modules.displayScale.DEBOUNCEMS"))
    }

    static Test_ModuleEnabled() {
        cfg := Config.FromText('{ "modules": { "a": {}, "b": { "enabled": false }, "c": true, "d": false } }')
        Assert.True(cfg.ModuleEnabled("a"))
        Assert.False(cfg.ModuleEnabled("b"))
        Assert.True(cfg.ModuleEnabled("c"))
        Assert.False(cfg.ModuleEnabled("d"))
        Assert.False(cfg.ModuleEnabled("missing"))
        Assert.True(cfg.ModuleEnabled("missing", true))
    }

    static Test_RejectsNonObjectRoot() {
        Assert.Throws(() => Config.FromText("[1, 2]"), "Top-level")
    }

    static Test_ReportsSyntaxErrors() {
        Assert.Throws(() => Config.FromText('{ "a": }'), "line 1")
    }

    static Test_FromFileNamesThePath() {
        path := A_Temp "\hotkit-bad-" A_TickCount ".json"
        FileAppend("{ nope", path, "UTF-8")
        try {
            e := Assert.Throws(() => Config.FromFile(path))
            Assert.Contains(e.Message, path)
        } finally {
            FileDelete(path)
        }
    }

    static Test_MapGet() {
        Assert.Equal(2, MapGet(Map("a", 2), "a", 9))
        Assert.Equal(9, MapGet(Map("a", 2), "b", 9))
        Assert.Equal(9, MapGet("not a map", "a", 9))
    }

    static Test_FromFileLoadsValidJson() {
        path := A_Temp "\hotkit-good-" A_TickCount ".json"
        FileAppend('{ "a": { "b": 2 } } // trailing comment', path, "UTF-8")
        try {
            cfg := Config.FromFile(path)
            Assert.Equal(2, cfg.Get("a.b"))
        } finally {
            FileDelete(path)
        }
    }
}
TestRunner.Add(Config_Tests)
