#Requires AutoHotkey v2.0

class ActionRegistry_Tests {
    static Setup() {
        ActionRegistry.Clear()
        ActionRegistry.OnError := ""
    }

    static Test_RegisterAndInvokeWithArgs() {
        ActionRegistry.Register("math.add", (a, b) => a + b, { description: "Add" })
        Assert.Equal(5, ActionRegistry.Invoke("math.add", [2, 3]))
        Assert.Equal("Add", ActionRegistry.Get("math.add").description)
    }

    static Test_InvokeWrapsScalarArg() {
        ActionRegistry.Register("echo", (x) => x)
        Assert.Equal("hi", ActionRegistry.Invoke("echo", "hi"))
    }

    static Test_IdsAreCaseInsensitive() {
        ActionRegistry.Register("app.Toggle", (*) => "ok")
        Assert.True(ActionRegistry.Has("APP.toggle"))
    }

    static Test_RejectsInvalidIds() {
        Assert.Throws(() => ActionRegistry.Register("bad id", (*) => 0), "Invalid action id")
        Assert.Throws(() => ActionRegistry.Register("1abc", (*) => 0), "Invalid action id")
        Assert.Throws(() => ActionRegistry.Register("a..b", (*) => 0), "Invalid action id")
        Assert.Throws(() => ActionRegistry.Register("ok", "not callable"), "not callable")
    }

    static Test_UnknownActionThrows() {
        Assert.Throws(() => ActionRegistry.Invoke("nope"), "Unknown action")
    }

    static Test_ListIsSorted() {
        ActionRegistry.Register("b.x", (*) => 0)
        ActionRegistry.Register("a.y", (*) => 0)
        ActionRegistry.Register("c", (*) => 0)
        ids := []
        for a in ActionRegistry.List()
            ids.Push(a.id)
        Assert.Equal(["a.y", "b.x", "c"], ids)
    }

    static Test_SafeInvokeReportsErrors() {
        seen := []
        ActionRegistry.OnError := (id, e) => seen.Push(id ": " e.Message)
        ActionRegistry.Register("boom", (*) => (_ := 1 / 0))
        ActionRegistry.SafeInvoke("boom")
        ActionRegistry.SafeInvoke("missing")
        Assert.Equal(2, seen.Length)
        Assert.Contains(seen[1], "boom")
        Assert.Contains(seen[2], "Unknown action")
    }

    static Test_ParseRef() {
        r := ActionRegistry.ParseRef("x.y")
        Assert.Equal("x.y", r.action)
        Assert.Equal([], r.args)
        r := ActionRegistry.ParseRef(Map("action", "x", "args", [1, "a"]))
        Assert.Equal([1, "a"], r.args)
        r := ActionRegistry.ParseRef(Map("action", "x", "args", 5))
        Assert.Equal([5], r.args)
        Assert.Throws(() => ActionRegistry.ParseRef(Map("args", [])), "action")
        Assert.Throws(() => ActionRegistry.ParseRef(42), "action")
    }

    static Test_CallbackInvokesAction() {
        calls := []
        ActionRegistry.Register("rec", (v) => calls.Push(v))
        cb := ActionRegistry.Callback(Map("action", "rec", "args", ["z"]))
        cb.Call("menu item", 1, "menu")
        Assert.Equal(["z"], calls)
    }

    static Test_Unregister() {
        ActionRegistry.Register("tmp", (*) => 0)
        ActionRegistry.Unregister("tmp")
        Assert.False(ActionRegistry.Has("tmp"))
    }

    static Test_RegisterReturnsInfo() {
        info := ActionRegistry.Register("t.info", (*) => 0, { description: "Info", module: "m", params: "p" })
        Assert.Equal("t.info", info.id)
        Assert.Equal("Info", info.description)
        Assert.Equal("m", info.module)
    }
}
TestRunner.Add(ActionRegistry_Tests)
