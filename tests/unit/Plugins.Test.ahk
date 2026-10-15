#Requires AutoHotkey v2.0

class Plugins_Tests {
    static Dir := ""

    static Setup() {
        ; Discover returns long paths; A_Temp can be an 8.3 short path (e.g. on CI runners).
        Plugins_Tests.Dir := Plugins_Tests.LongPath(A_Temp) "\hotkit-plugins-" A_TickCount
        DirCreate(Plugins_Tests.Dir "\plugins\lib")
    }

    static LongPath(path) {
        loop files path, "D"
            return A_LoopFileFullPath
        return path
    }

    static Teardown() {
        try DirDelete(Plugins_Tests.Dir, true)
    }

    static Test_DiscoverTopLevelAhkOnly() {
        d := Plugins_Tests.Dir "\plugins"
        FileAppend("", d "\b.ahk")
        FileAppend("", d "\a.ahk")
        FileAppend("", d "\notes.txt")
        FileAppend("", d "\lib\helper.ahk")
        found := Plugins.Discover(d)
        Assert.Equal([d "\a.ahk", d "\b.ahk"], found)
    }

    static Test_MissingDirIsEmpty() {
        Assert.Equal(0, Plugins.Discover(Plugins_Tests.Dir "\nope").Length)
    }

    static Test_RenderIncludesOptionally() {
        text := Plugins.Render(["C:\x\p.ahk"])
        Assert.Contains(text, "#Include *i C:\x\p.ahk`n")
        Assert.Contains(text, "Do not edit")
    }

    static Test_SyncWritesOnlyOnChange() {
        d := Plugins_Tests.Dir "\plugins"
        stub := Plugins_Tests.Dir "\local\stub.ahk"
        Assert.True(Plugins.Sync(stub, d), "first sync creates the stub")
        Assert.False(Plugins.Sync(stub, d), "unchanged plugin set")
        FileAppend("", d "\new.ahk")
        Assert.True(Plugins.Sync(stub, d), "new plugin detected")
        Assert.Contains(FileRead(stub), d "\new.ahk")
    }

    static Test_IsCurrentTracksPluginSet() {
        d := Plugins_Tests.Dir "\plugins"
        stub := Plugins_Tests.Dir "\local\stub.ahk"
        Assert.False(Plugins.IsCurrent(stub, d), "missing stub is stale")
        Plugins.Sync(stub, d)
        Assert.True(Plugins.IsCurrent(stub, d))
        FileAppend("", d "\added.ahk")
        Assert.False(Plugins.IsCurrent(stub, d), "added plugin makes the stub stale")
    }
}
TestRunner.Add(Plugins_Tests)
