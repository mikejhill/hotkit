#Requires AutoHotkey v2.0

class Plugins_Tests {
    static Dir := ""

    static Setup() {
        Plugins_Tests.Dir := A_Temp "\hotkit-plugins-" A_TickCount
        DirCreate(Plugins_Tests.Dir "\plugins\lib")
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
}
TestRunner.Add(Plugins_Tests)
