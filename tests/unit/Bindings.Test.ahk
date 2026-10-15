#Requires AutoHotkey v2.0

class Bindings_Tests {
    static Setup() {
        Bindings.Reset()
        ActionRegistry.Clear()
        ActionRegistry.Register("t.a", (*) => 0, { description: "Action A" })
        ActionRegistry.Register("t.b", (x := "") => 0)
    }

    static Teardown() => Bindings.Reset()

    ; Joins JSON fragments (AHK string literals cannot span lines).
    static Load(parts*) {
        text := ""
        for p in parts
            text .= p " "
        Bindings.LoadConfig(Config.FromText(text))
        Bindings.Validate()
        return Bindings.problems
    }

    static Test_SimpleBinding() {
        problems := Bindings_Tests.Load('{ "bindings": [ { "keys": "F13", "action": "t.a" } ] }')
        Assert.Equal(0, problems.Length)
        Assert.Equal(1, Bindings.specs.Length)
        Assert.Equal("Action A", Bindings.specs[1].description, "default description comes from the action")
    }

    static Test_DescriptionIncludesArgs() {
        Bindings_Tests.Load('{ "bindings": [ { "keys": "F13", "action": "t.b", "args": ["x", 2] } ] }')
        Assert.Equal("t.b (x, 2)", Bindings.specs[1].description)
    }

    static Test_MissingKeysAndBadShapes() {
        problems := Bindings_Tests.Load('{ "bindings": [ { "action": "t.a" }, 5, { "keys": "F1" } ] }')
        Assert.Equal(3, problems.Length)
        Assert.Contains(problems[1], "missing 'keys'")
        Assert.Contains(problems[2], "must be an object")
        Assert.Contains(problems[3], "action")
    }

    static Test_DisabledBindingsAreSkipped() {
        Bindings_Tests.Load('{ "bindings": [ { "keys": "F13", "action": "t.a", "enabled": false } ] }')
        Assert.Equal(0, Bindings.specs.Length)
    }

    static Test_UnknownActionIsReported() {
        problems := Bindings_Tests.Load('{ "bindings": [ { "keys": "F13", "action": "nope" } ] }')
        Assert.Equal(1, problems.Length)
        Assert.Contains(problems[1], "unknown action 'nope'")
    }

    static Test_UnknownLayerIsReported() {
        problems := Bindings_Tests.Load('{ "bindings": [ { "keys": "F13", "layer": "x", "action": "t.a" } ] }')
        Assert.Contains(problems[1], "unknown layer 'x'")
    }

    static Test_LayerWithoutKeyIsReported() {
        problems := Bindings_Tests.Load('{ "layers": { "bad": {} } }')
        Assert.Contains(problems[1], "Layer 'bad' has no key")
    }

    static Test_ConflictsDetectedPerContext() {
        problems := Bindings_Tests.Load(
            '{ "layers": { "caps": { "key": "CapsLock" } }, "bindings": [',
            '{ "keys": "F13", "action": "t.a" },',
            '{ "keys": "F13", "action": "t.a", "layer": "caps" },',
            '{ "keys": "f13", "action": "t.b" } ] }')
        Assert.Equal(1, problems.Length)
        Assert.Contains(problems[1], "Conflict")
    }

    static Test_GroupsAreImplicitAndToggle() {
        Bindings_Tests.Load('{ "bindings": [ { "keys": "F13", "action": "t.a", "group": "g" } ] }')
        Assert.True(Bindings.GroupEnabled("g"))
        Assert.False(Bindings.ToggleGroup("g"))
        Assert.False(Bindings.Rows()[1].active)
        Assert.True(Bindings.SetGroup("g", true))
        Assert.Throws(() => Bindings.SetGroup("missing", true), "Unknown binding group")
    }

    static Test_ExplicitGroupDefaults() {
        Bindings_Tests.Load('{ "groups": { "g": { "enabled": false, "description": "Gee" } } }')
        Assert.False(Bindings.GroupEnabled("g"))
        Assert.Equal("Gee", Bindings.groups["g"].description)
    }

    static Test_Gestures() {
        problems := Bindings_Tests.Load('{ "bindings": [ { "keys": "F23", "gestures": {',
            '"tap": "t.a", "doubleTap": { "action": "t.b", "args": [1] }, "hold": "nope", "holdMs": 300 } } ] }')
        Assert.Equal(1, problems.Length, "unknown action inside gestures is reported")
        spec := Bindings.specs[1]
        Assert.Equal("gestures", spec.kind)
        Assert.Equal(300, spec.gestures.holdMs)
        Assert.Equal(250, spec.gestures.doubleTapMs)
        Assert.Equal("tap: t.a, doubleTap: t.b, hold: nope", spec.description)
    }

    static Test_EmptyGesturesRejected() {
        problems := Bindings_Tests.Load('{ "bindings": [ { "keys": "F23", "gestures": {} } ] }')
        Assert.Contains(problems[1], "at least one")
    }

    static Test_HoldBinding() {
        problems := Bindings_Tests.Load('{ "bindings": [ { "keys": "Space", "action": "t.a", "onRelease": "t.b" } ] }')
        Assert.Equal(0, problems.Length)
        Assert.Equal("hold", Bindings.specs[1].kind)
        Assert.Equal("t.b", Bindings.specs[1].onRelease.action)
    }

    static Test_RowsUseLayerLabels() {
        Bindings_Tests.Load('{ "layers": { "caps": { "key": "CapsLock", "label": "Caps" } },',
            '"bindings": [ { "keys": "<^c", "layer": "caps", "action": "t.a", "description": "Do it" } ] }')
        row := Bindings.Rows()[1]
        Assert.Equal("Caps+LCtrl+C", row.keys)
        Assert.Equal("Do it", row.description)
        Assert.Equal("t.a", row.action)
    }

    static Test_ApplyRegistersAndUnregisters() {
        Bindings_Tests.Load('{ "layers": { "caps": { "key": "CapsLock" } }, "bindings": [',
            '{ "keys": "F20", "action": "t.a" },',
            '{ "keys": "F20", "layer": "caps", "action": "t.b" },',
            '{ "keys": "Space", "layer": "caps", "action": "t.a", "onRelease": "t.b" },',
            '{ "keys": "F21", "gestures": { "tap": "t.a" } },',
            '{ "keys": "F22", "action": "t.a", "waitRelease": true } ] }')
        problems := Bindings.Apply()
        Assert.Equal(0, problems.Length, "apply problems: " (problems.Length ? problems[1] : ""))
        ; 5 bindings + 2 extra hotkeys for the hold binding's release tracking.
        Assert.Equal(7, Bindings._registered.Length)
        Bindings.UnregisterAll()
        Assert.Equal(0, Bindings._registered.Length)
    }

    static Test_InvalidKeyNameIsAProblemNotACrash() {
        Bindings_Tests.Load('{ "bindings": [ { "keys": "NotAKey123", "action": "t.a" } ] }')
        problems := Bindings.Apply()
        Assert.Equal(1, problems.Length)
        Assert.Contains(problems[1], "NotAKey123")
    }

    static Test_ContextsAreShared() {
        Bindings_Tests.Load('{ "layers": { "caps": { "key": "CapsLock" } }, "bindings": [',
            '{ "keys": "F20", "layer": "caps", "action": "t.a" },',
            '{ "keys": "F21", "layer": "caps", "action": "t.a" } ] }')
        Assert.True(Bindings._Context(Bindings.specs[1]) == Bindings._Context(Bindings.specs[2]))
        Assert.Equal("", Bindings._Context({ layer: "", group: "", whenActive: "" }))
    }

    static Test_ReturnValues() {
        cfg := Config.FromText('{ "bindings": [ { "action": "t.a" } ] }')
        Assert.Equal(1, Bindings.LoadConfig(cfg).Length, "LoadConfig returns the problem list")
        spec := Bindings.Add(Map("keys", "F14", "action", "t.a"))
        Assert.Equal("F14", spec.keys)
        Assert.False(spec.waitRelease, "waitRelease defaults to false")
        Assert.Equal("", Bindings.Add(Map("action", "t.a")), "invalid bindings return an empty string")
        Assert.True(Bindings.Validate() == Bindings.problems, "Validate returns the problem list")
        Assert.Equal(2, Bindings.problems.Length)
    }

    static Test_GroupsDefaultToEnabled() {
        Bindings_Tests.Load('{ "groups": { "g": { "description": "Gee" } } }')
        Assert.True(Bindings.GroupEnabled("g"))
    }

    static Test_BindingDoesNotRedefineExplicitGroup() {
        Bindings_Tests.Load('{ "groups": { "g": { "enabled": false, "description": "Gee" } },',
            '"bindings": [ { "keys": "F13", "action": "t.a", "group": "g" } ] }')
        Assert.False(Bindings.GroupEnabled("g"), "a binding must not reset its group's state")
        Assert.Equal("Gee", Bindings.groups["g"].description)
    }

    static Test_RowsActiveState() {
        Bindings_Tests.Load('{ "groups": { "off": { "enabled": false } },',
            '"bindings": [ { "keys": "F13", "action": "t.a" }, { "keys": "F14", "action": "t.a", "group": "off" } ] }')
        rows := Bindings.Rows()
        Assert.True(rows[1].active, "ungrouped bindings are always active")
        Assert.False(rows[2].active)
    }
}
TestRunner.Add(Bindings_Tests)
