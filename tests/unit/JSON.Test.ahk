#Requires AutoHotkey v2.0

class JSON_Tests {
    static Test_RoundTrip() {
        text := '{"a":[1,2.5,"x\"y"],"b":true,"c":null,"d":{"e":false}}'
        Assert.Equal(text, JSON.Stringify(JSON.Parse(text)))
    }

    static Test_MapKeysSerializeSorted() {
        ; AHK Maps enumerate keys in sorted order, so output order is deterministic.
        Assert.Equal('{"a":2,"z":1}', JSON.Stringify(JSON.Parse('{"z":1,"a":2}')))
    }

    static Test_UnicodeEscapes() {
        Assert.Equal("é😀", JSON.Parse('"é😀"'))
    }

    static Test_PrettyPrint() {
        Assert.Equal('{`n  "a": [`n    1`n  ]`n}', JSON.Stringify(Map("a", [1]), { pretty: true }))
    }

    static Test_Errors() {
        Assert.Throws(() => JSON.Parse(""), "empty input")
        Assert.Throws(() => JSON.Parse("[1,]"), "line 1")
        Assert.Throws(() => JSON.Parse("{} x"), "trailing")
        Assert.Throws(() => JSON.Parse("// c`n{}"))
    }

    static Test_LenientOptions() {
        v := JSON.Parse("// c`n{ /* x */ `"a`": [1,], }", { allowComments: true, allowTrailingCommas: true })
        Assert.Equal([1], v["a"])
    }

    static Test_Numbers() {
        v := JSON.Parse("[0, -1, 1e3, 2.5E-1, 12345678901]")
        Assert.Equal(0, v[1])
        Assert.Equal(-1, v[2])
        Assert.Near(1000, v[3])
        Assert.Near(0.25, v[4])
        Assert.Equal(12345678901, v[5])
    }
}
TestRunner.Add(JSON_Tests)
