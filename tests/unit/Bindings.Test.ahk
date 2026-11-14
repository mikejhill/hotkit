#Requires AutoHotkey v2.0

class Bindings_Tests {
    static Setup() {
        Bindings.Reset()
        ActionRegistry.Clear()
        ActionRegistry.Register("t.a", (*) => 0, { description: "Action A" })
        ActionRegistry.Register("t.b", (x := "") => 0)
    }

    static Teardown() {
        Bindings.Reset()
        Bindings_Tests.RestoreHookFactory()
    }

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

    static Test_ModifierWithoutKeyIsReported() {
        problems := Bindings_Tests.Load('{ "modifiers": { "bad": {} } }')
        Assert.Contains(problems[1], "Modifier 'bad' has no key")
    }

    static Test_ConflictsDetectedPerContext() {
        problems := Bindings_Tests.Load(
            '{ "modifiers": { "caps": { "key": "CapsLock" } }, "bindings": [',
            '{ "keys": "F13", "action": "t.a" },',
            '{ "keys": "F13", "action": "t.a", "modifier": "caps" },',
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

    ; ---- Hold and latch bindings ----

    static calls := []

    ; Registers recording actions t.start / t.stop / t.cancel and a fake latch
    ; hook factory, so no real keyboard hook is installed.
    static UseRecorder() {
        Bindings_Tests.calls := []
        calls := Bindings_Tests.calls
        for name in ["start", "stop", "cancel", "start2", "stop2"] {
            n := name
            ActionRegistry.Register("t." n, ((n, *) => calls.Push(n)).Bind(n))
        }
        Bindings.LatchHookFactory := (*) => FakeLatchHook()
    }

    static RestoreHookFactory() => Bindings.LatchHookFactory := (*) => InputHook("L0 I V")

    static Joined(list) {
        out := ""
        for i, x in list
            out .= (i = 1 ? "" : ",") x
        return out
    }

    static LoadKeyBindings(bindingsJson) {
        Bindings_Tests.UseRecorder()
        problems := Bindings_Tests.Load('{ "modifiers": { "caps": { "key": "CapsLock" } }, "bindings": [', bindingsJson, '] }')
        Assert.Equal(0, problems.Length, problems.Length ? problems[1] : "")
    }

    static Test_LatchBindingParses() {
        Bindings_Tests.LoadKeyBindings('{ "keys": "^Space", "modifier": "caps", "action": "t.start", "onNextKey": "t.stop", "onCancel": "t.cancel", "exclusive": "rec" }')
        spec := Bindings.specs[1]
        Assert.Equal("latch", spec.kind)
        Assert.Equal("t.stop", spec.onNextKey.action)
        Assert.Equal("t.cancel", spec.onCancel.action)
        Assert.Equal("rec", spec.exclusive)
        Assert.Equal(3, Bindings._Refs(spec).Length)
    }

    static Test_LatchAndHoldFieldProblems() {
        Bindings_Tests.UseRecorder()
        problems := Bindings_Tests.Load('{ "bindings": [',
            '{ "keys": "F1", "action": "t.start", "onRelease": "t.stop", "onNextKey": "t.stop" },',
            '{ "keys": "F2", "action": "t.start", "onCancel": "t.cancel" },',
            '{ "keys": "F3", "action": "t.start", "exclusive": "rec" },',
            '{ "keys": "F4", "gestures": { "tap": "t.start" }, "onNextKey": "t.stop" },',
            '{ "keys": "F5 UP", "action": "t.start", "onNextKey": "t.stop" },',
            '{ "keys": "F6", "action": "t.start", "onNextKey": "nope" } ] }')
        Assert.Equal(6, problems.Length)
        Assert.Contains(problems[1], "not both")
        Assert.Contains(problems[2], "'onCancel' needs 'onNextKey'")
        Assert.Contains(problems[3], "'exclusive' needs")
        Assert.Contains(problems[4], "can't be combined with 'gestures'")
        Assert.Contains(problems[5], "key-down")
        Assert.Contains(problems[6], "unknown action 'nope'")
    }

    static Test_HoldIgnoresRepeatAndStopsOnce() {
        Bindings_Tests.LoadKeyBindings('{ "keys": "Space", "modifier": "caps", "action": "t.start", "onRelease": "t.stop" }')
        spec := Bindings.specs[1], state := Bindings.NewKeyState()
        Bindings.HoldPress(spec, state)
        Bindings.HoldPress(spec, state)          ; auto-repeat
        Bindings.HoldEnd(spec, state)            ; modifier released first
        state.baseDown := false                  ; then the key
        Bindings.HoldEnd(spec, state)
        Assert.Equal("start,stop", Bindings_Tests.Joined(Bindings_Tests.calls))
    }

    static Test_HoldModifierKeyIsTheBindingModifier() {
        Bindings_Tests.LoadKeyBindings('{ "keys": "+Space", "modifier": "caps", "action": "t.start", "onRelease": "t.stop" }')
        Assert.Equal("CapsLock", Bindings.ModifierKey(Bindings.specs[1]))
    }

    static Test_LatchStopsOnNextKeyAndConsumesIt() {
        Bindings_Tests.LoadKeyBindings('{ "keys": "^Space", "modifier": "caps", "action": "t.start", "onNextKey": "t.stop", "onCancel": "t.cancel" }')
        spec := Bindings.specs[1], state := Bindings.NewKeyState()
        Bindings.LatchPress(spec, state)
        hook := state.hook
        Assert.True(hook.started)
        Assert.Equal("ES", hook.opts["{All}"])
        Assert.Equal("-ES", hook.opts[Bindings.LatchIgnoredKeys], "modifiers never end a latch")
        Assert.Equal("-ES", hook.opts[Bindings.KeyOptKeys("Space")], "the chord key doesn't end it while held")
        Assert.Equal("-ES", hook.opts[Bindings.KeyOptKeys("CapsLock")], "nor does the held modifier key")
        Bindings.LatchPress(spec, state)          ; auto-repeat
        Assert.Equal("start", Bindings_Tests.Joined(Bindings_Tests.calls))
        state.baseDown := false
        Bindings.LatchKeyReleased(state, "Space")
        Assert.Equal("+ES", hook.opts[Bindings.KeyOptKeys("Space")], "a released chord key ends it on its next press")
        hook.Finish("EndKey", "Enter")
        Bindings.LatchHookEnded(spec, state, hook)
        Assert.Equal("start,stop", Bindings_Tests.Joined(Bindings_Tests.calls))
        Assert.False(state.active)
        Assert.Equal("Enter", Bindings._rearmKey)
    }

    static Test_LatchEscapeCancels() {
        Bindings_Tests.LoadKeyBindings('{ "keys": "^Space", "action": "t.start", "onNextKey": "t.stop", "onCancel": "t.cancel" }')
        spec := Bindings.specs[1], state := Bindings.NewKeyState()
        Bindings.LatchPress(spec, state)
        hook := state.hook
        hook.Finish("EndKey", "Escape")
        Bindings.LatchHookEnded(spec, state, hook)
        Assert.Equal("start,cancel", Bindings_Tests.Joined(Bindings_Tests.calls))
    }

    static Test_LatchEscapeWithoutOnCancelStops() {
        Bindings_Tests.LoadKeyBindings('{ "keys": "^Space", "action": "t.start", "onNextKey": "t.stop" }')
        Assert.Equal("t.stop", Bindings.LatchStopRef(Bindings.specs[1], "Escape").action)
    }

    static Test_StoppedLatchHookRunsNothing() {
        Bindings_Tests.LoadKeyBindings('{ "keys": "^Space", "action": "t.start", "onNextKey": "t.stop" }')
        spec := Bindings.specs[1], state := Bindings.NewKeyState()
        Bindings.LatchPress(spec, state)
        hook := state.hook
        hook.Finish("Stopped", "")
        Bindings.LatchHookEnded(spec, state, hook)
        Assert.Equal("start", Bindings_Tests.Joined(Bindings_Tests.calls))
        Assert.True(state.active, "still recording; only a key ends it")
    }

    static Test_LatchChordAgainStops() {
        Bindings_Tests.LoadKeyBindings('{ "keys": "^Space", "action": "t.start", "onNextKey": "t.stop" }')
        spec := Bindings.specs[1], state := Bindings.NewKeyState()
        Bindings.LatchPress(spec, state)
        hook := state.hook
        state.baseDown := false
        Bindings.LatchPress(spec, state)
        Assert.Equal("start,stop", Bindings_Tests.Joined(Bindings_Tests.calls))
        Assert.True(hook.stopped, "the waiting hook is stopped")
    }

    static Test_ExclusiveStopsActiveInsteadOfStarting() {
        Bindings_Tests.LoadKeyBindings(
            '{ "keys": "Space", "action": "t.start", "onRelease": "t.stop", "exclusive": "rec" },'
            . '{ "keys": "^Space", "action": "t.start2", "onNextKey": "t.stop2", "exclusive": "rec" }')
        hold := Bindings.specs[1], latch := Bindings.specs[2]
        holdState := Bindings.NewKeyState(), latchState := Bindings.NewKeyState()
        Bindings.LatchPress(latch, latchState)
        Bindings.HoldPress(hold, holdState)       ; stops the latch, starts nothing
        Assert.Equal("start2,stop2", Bindings_Tests.Joined(Bindings_Tests.calls))
        Assert.False(holdState.active)
        holdState.baseDown := false
        Bindings.HoldPress(hold, holdState)       ; nothing active now: starts
        Bindings.HoldEnd(hold, holdState)
        Assert.Equal("start2,stop2,start,stop", Bindings_Tests.Joined(Bindings_Tests.calls))
        Assert.Equal(0, Bindings._sessions.Count)
    }

    static Test_RearmKeyBlocksStartsUntilReleased() {
        Bindings_Tests.LoadKeyBindings('{ "keys": "Space", "action": "t.start", "onRelease": "t.stop" }')
        spec := Bindings.specs[1], state := Bindings.NewKeyState()
        ; F24 is not physically held, so the rearm key clears and the press starts.
        Bindings._rearmKey := "F24"
        Bindings.HoldPress(spec, state)
        Assert.Equal("start", Bindings_Tests.Joined(Bindings_Tests.calls))
        Assert.Equal("", Bindings._rearmKey)
    }

    static Test_ApplyRegistersLatchKeys() {
        Bindings_Tests.LoadKeyBindings(
            '{ "keys": "^Space", "modifier": "caps", "action": "t.start", "onNextKey": "t.stop" },'
            . '{ "keys": "Space", "modifier": "caps", "action": "t.start", "onRelease": "t.stop" }')
        problems := Bindings.Apply()
        Assert.Equal(0, problems.Length, problems.Length ? problems[1] : "")
        ; Two hotkeys, plus one shared repeat swallow, Space up and CapsLock up.
        Assert.Equal(5, Bindings._registered.Length)
        Bindings.UnregisterAll()
        Bindings_Tests.RestoreHookFactory()
    }

    static Test_ReleasedModifierKeyNeverEndsLatch() {
        Bindings_Tests.UseRecorder()
        Bindings_Tests.Load('{ "modifiers": { "ctl": { "key": "LCtrl" } }, "bindings": [',
            '{ "keys": "Space", "modifier": "ctl", "action": "t.start", "onNextKey": "t.stop" } ] }')
        spec := Bindings.specs[1], state := Bindings.NewKeyState()
        Bindings.LatchPress(spec, state)
        hook := state.hook
        Bindings.LatchKeyReleased(state, "LCtrl")
        Assert.False(hook.opts.Has(Bindings.KeyOptKeys("LCtrl")) && hook.opts[Bindings.KeyOptKeys("LCtrl")] = "+ES")
        Assert.True(Bindings.IsLatchIgnoredKey("rshift"))
        Assert.False(Bindings.IsLatchIgnoredKey("CapsLock"))
    }

    static Test_ReleaseRunsEveryActiveWatcher() {
        calls := []
        a := { on: true }, b := { on: true }, c := { on: false }
        list := [
            { active: () => a.on, run: () => (a.on := false, calls.Push("a")) },
            { active: () => b.on, run: () => (b.on := false, calls.Push("b")) },
            { active: () => c.on, run: () => calls.Push("c") }
        ]
        Bindings.RunActiveWatchers(list)
        Assert.Equal("a,b", Bindings_Tests.Joined(calls))
    }

    static Test_RowsUseModifierLabels() {
        Bindings_Tests.Load('{ "modifiers": { "caps": { "key": "CapsLock", "label": "Caps" } },',
            '"bindings": [ { "keys": "<^c", "modifier": "caps", "action": "t.a", "description": "Do it" } ] }')
        row := Bindings.Rows()[1]
        Assert.Equal("Caps+LCtrl+C", row.keys)
        Assert.Equal("Do it", row.description)
        Assert.Equal("t.a", row.action)
    }

    static Test_ApplyRegistersAndUnregisters() {
        Bindings_Tests.Load('{ "modifiers": { "caps": { "key": "CapsLock" } }, "bindings": [',
            '{ "keys": "F20", "action": "t.a" },',
            '{ "keys": "F20", "modifier": "caps", "action": "t.b" },',
            '{ "keys": "Space", "modifier": "caps", "action": "t.a", "onRelease": "t.b" },',
            '{ "keys": "F21", "gestures": { "tap": "t.a" } },',
            '{ "keys": "F22", "action": "t.a", "waitRelease": true } ] }')
        problems := Bindings.Apply()
        Assert.Equal(0, problems.Length, "apply problems: " (problems.Length ? problems[1] : ""))
        ; 5 bindings + 3 extra hotkeys for the hold binding's release tracking
        ; (repeat swallow, key up, modifier key up).
        Assert.Equal(8, Bindings._registered.Length)
        Bindings.UnregisterAll()
        Assert.Equal(0, Bindings._registered.Length)
    }

    static Test_InvalidKeyNameIsAProblemNotACrash() {
        Bindings_Tests.Load('{ "bindings": [ { "keys": "NotAKey123", "action": "t.a" } ] }')
        problems := Bindings.Apply()
        Assert.Equal(1, problems.Length)
        Assert.Contains(problems[1], "NotAKey123")
    }

    static Test_ModifierSuspendWhenActiveAcceptsStringOrList() {
        problems := Bindings_Tests.Load('{ "modifiers": {',
            '"a": { "key": "CapsLock", "suspendWhenActive": "ahk_exe One.exe" },',
            '"b": { "key": "F20", "suspendWhenActive": ["ahk_exe One.exe", "ahk_exe Two.exe"] },',
            '"c": { "key": "F21" } } }')
        Assert.Equal(0, problems.Length)
        Assert.Equal(1, Bindings.modifiers["a"].suspendWhenActive.Length)
        Assert.Equal("ahk_exe Two.exe", Bindings.modifiers["b"].suspendWhenActive[2])
        Assert.Equal(0, Bindings.modifiers["c"].suspendWhenActive.Length)
    }

    static Test_ModifierSuspendWhenActiveRejectsBadEntries() {
        problems := Bindings_Tests.Load('{ "modifiers": { "a": { "key": "CapsLock", "suspendWhenActive": ["", 5, "ahk_exe One.exe"] } } }')
        Assert.Equal(2, problems.Length)
        Assert.Contains(problems[1], "suspendWhenActive")
        Assert.Equal(1, Bindings.modifiers["a"].suspendWhenActive.Length)
    }

    static Test_ModifierSuspendedOnlyWhileListedWindowActive() {
        Bindings_Tests.Load('{ "modifiers": { "a": { "key": "CapsLock", "suspendWhenActive": "ahk_exe NoSuchHotkitProcess.exe" },',
            '"b": { "key": "F20" } } }')
        Assert.False(Bindings.ModifierSuspended(Bindings.modifiers["a"]))
        Assert.False(Bindings.ModifierSuspended(Bindings.modifiers["b"]))
        Bindings.modifiers["a"].suspendWhenActive.Push("A")  ; "A" = the active window
        if WinExist("A")
            Assert.True(Bindings.ModifierSuspended(Bindings.modifiers["a"]))
    }

    static Test_ContextsAreShared() {
        Bindings_Tests.Load('{ "modifiers": { "caps": { "key": "CapsLock" } }, "bindings": [',
            '{ "keys": "F20", "modifier": "caps", "action": "t.a" },',
            '{ "keys": "F21", "modifier": "caps", "action": "t.a" } ] }')
        Assert.True(Bindings._Context(Bindings.specs[1]) == Bindings._Context(Bindings.specs[2]))
        Assert.Equal("", Bindings._Context({ modifier: "", layers: [], group: "", whenActive: "" }))
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

    ; ---------------- Switchable layers ----------------

    static Test_LayersFromListKeepOrderAndDefaultToFirst() {
        problems := Bindings_Tests.Load('{ "layers": ["2", "1", 10] }')
        Assert.Equal(0, problems.Length)
        Assert.Equal("2,1,10", Bindings_Tests.Join(Bindings.layerOrder))
        Assert.Equal("2", Bindings.activeLayer)
        Assert.Equal("Layer 10", Bindings.layers["10"].label)
    }

    static Test_LayersFromObjectUseNaturalOrderAndDefault() {
        problems := Bindings_Tests.Load('{ "layers": { "10": {}, "2": { "label": "Games", "description": "Gaming keys" },',
            '"b": {}, "1": {}, "a": { "default": true } } }')
        Assert.Equal(0, problems.Length)
        Assert.Equal("1,2,10,a,b", Bindings_Tests.Join(Bindings.layerOrder))
        Assert.Equal("a", Bindings.activeLayer)
        Assert.Equal("Games", Bindings.layers["2"].label)
        Assert.Equal("Gaming keys", Bindings.layers["2"].description)
        Assert.Equal("a", Bindings.layers["A"].label)
    }

    static Test_NoLayersMeansNoActiveLayer() {
        Bindings_Tests.Load('{ "bindings": [ { "keys": "F13", "action": "t.a" } ] }')
        Assert.Equal("", Bindings.activeLayer)
        Assert.True(Bindings.Rows()[1].onLayer)
    }

    static Test_BadLayerDefinitionsAreReported() {
        problems := Bindings_Tests.Load('{ "layers": ["1", "", {}] }')
        Assert.Equal(2, problems.Length)
        Bindings.Reset()
        problems := Bindings_Tests.Load('{ "layers": { "1": [] } }')
        Assert.Contains(problems[1], "settings must be an object")
        Bindings.Reset()
        problems := Bindings_Tests.Load('{ "layers": "1" }')
        Assert.Contains(problems[1], "'layers' must be")
    }

    static Test_BindingLayerAcceptsNameNumberOrList() {
        problems := Bindings_Tests.Load('{ "layers": ["1", "2", "3"], "bindings": [',
            '{ "keys": "F13", "action": "t.a", "layer": "1" },',
            '{ "keys": "F14", "action": "t.a", "layer": 2 },',
            '{ "keys": "F15", "action": "t.a", "layer": ["1", 3, "1"] },',
            '{ "keys": "F16", "action": "t.a" },',
            '{ "keys": "F17", "action": "t.a", "layer": "nope" },',
            '{ "keys": "F18", "action": "t.a", "layer": ["1", "nope"] } ] }')
        Assert.Equal(2, problems.Length)
        Assert.Contains(problems[1], "unknown layer 'nope'")
        Assert.Equal(4, Bindings.specs.Length)
        Assert.Equal("1", Bindings_Tests.Join(Bindings.specs[1].layers))
        Assert.Equal("2", Bindings_Tests.Join(Bindings.specs[2].layers))
        Assert.Equal("1,3", Bindings_Tests.Join(Bindings.specs[3].layers))
        Assert.Equal(0, Bindings.specs[4].layers.Length)
    }

    static Test_SetLayerAndRowsFollowActiveLayer() {
        Bindings_Tests.Load('{ "layers": ["1", "2"], "bindings": [',
            '{ "keys": "F13", "action": "t.a", "layer": "1" },',
            '{ "keys": "F14", "action": "t.a", "layer": "2" },',
            '{ "keys": "F15", "action": "t.a" } ] }')
        rows := Bindings.Rows()
        Assert.True(rows[1].onLayer && rows[1].active)
        Assert.False(rows[2].onLayer || rows[2].active)
        Assert.True(rows[3].onLayer)
        Assert.Equal("Layer 2", rows[2].layers)
        Assert.Equal("2", Bindings.SetLayer(2))
        rows := Bindings.Rows()
        Assert.False(rows[1].active)
        Assert.True(rows[2].active)
        Assert.Throws(() => Bindings.SetLayer("9"), "Unknown layer")
        Assert.Equal("2", Bindings.activeLayer, "a failed switch keeps the layer")
    }

    static Test_StepLayerWraps() {
        order := ["1", "2", "3"]
        Assert.Equal("2", Bindings.StepLayer(order, "1", 1))
        Assert.Equal("1", Bindings.StepLayer(order, "3", 1))
        Assert.Equal("3", Bindings.StepLayer(order, "1", -1))
        Assert.Equal("1", Bindings.StepLayer(order, "missing", 1))
        Assert.Equal("", Bindings.StepLayer([], "1", 1))
    }

    static Test_LayerConflicts() {
        problems := Bindings_Tests.Load('{ "layers": ["1", "2"], "bindings": [',
            '{ "keys": "F13", "action": "t.a", "layer": "1" },',
            '{ "keys": "F13", "action": "t.a", "layer": "2" },',
            '{ "keys": "F13", "action": "t.a" },',
            '{ "keys": "F14", "action": "t.a", "layer": ["1", "2"] },',
            '{ "keys": "F14", "action": "t.a", "layer": "2" } ] }')
        Assert.Equal(1, problems.Length, "only overlapping layer lists conflict")
        Assert.Contains(problems[1], "'F14'")
    }

    static Test_LayerContextFollowsActiveLayer() {
        Bindings_Tests.Load('{ "layers": ["1", "2"], "bindings": [',
            '{ "keys": "F13", "action": "t.a", "layer": "1" },',
            '{ "keys": "F14", "action": "t.a", "layer": "1" },',
            '{ "keys": "F15", "action": "t.a", "layer": ["1", "2"] } ] }')
        one := Bindings._Context(Bindings.specs[1])
        Assert.True(one == Bindings._Context(Bindings.specs[2]), "same layer shares a context")
        both := Bindings._Context(Bindings.specs[3])
        Assert.True(one() && both())
        Bindings.SetLayer("2")
        Assert.False(one())
        Assert.True(both())
    }

    static Test_ApplyRegistersLayerBindingsFirst() {
        Bindings_Tests.Load('{ "layers": ["1"], "bindings": [',
            '{ "keys": "F20", "action": "t.a" },',
            '{ "keys": "F20", "action": "t.b", "layer": "1" } ] }')
        problems := Bindings.Apply()
        Assert.Equal(0, problems.Length)
        Assert.True(IsObject(Bindings._registered[1].context), "layer binding registered first")
        Assert.Equal("", Bindings._registered[2].context)
    }

    static Test_LegacyKeyedLayerBecomesModifier() {
        problems := Bindings_Tests.Load('{ "layers": { "caps": { "key": "CapsLock" }, "1": {} }, "bindings": [',
            '{ "keys": "F13", "action": "t.a", "layer": "caps" },',
            '{ "keys": "F14", "action": "t.a", "layer": "1" } ] }')
        Assert.Equal(1, problems.Length)
        Assert.Contains(problems[1], "now modifiers")
        Assert.Equal("caps", Bindings.specs[1].modifier)
        Assert.Equal(0, Bindings.specs[1].layers.Length)
        Assert.Equal("1", Bindings.layerOrder[1])
        Assert.Equal(1, Bindings.layerOrder.Length)
    }

    static Test_LegacyLayerWithEmptyKeyIsReportedNotThrown() {
        problems := Bindings_Tests.Load('{ "layers": { "caps": { "key": "" } }, "bindings": [ { "keys": "F13", "action": "t.a" } ] }')
        Assert.Contains(problems[1], "has no key")
        Assert.Equal(1, Bindings.specs.Length)
    }

    static Test_LayerListsWithCommasGetDistinctContexts() {
        Bindings_Tests.Load('{ "layers": ["a", "b", "a,b"], "bindings": [',
            '{ "keys": "F13", "action": "t.a", "layer": "a,b" },',
            '{ "keys": "F14", "action": "t.a", "layer": ["a", "b"] } ] }')
        one := Bindings._Context(Bindings.specs[1])
        two := Bindings._Context(Bindings.specs[2])
        Assert.False(one == two)
        Assert.False(one())
        Assert.True(two())
    }

    static Test_LegacyShorthandLayerBecomesModifier() {
        problems := Bindings_Tests.Load('{ "layers": { "caps": "CapsLock" }, "bindings": [ { "keys": "F13", "action": "t.a", "layer": "caps" } ] }')
        Assert.Equal(1, problems.Length)
        Assert.Contains(problems[1], "now modifiers")
        Assert.Equal("CapsLock", Bindings.modifiers["caps"].key)
        Assert.Equal("caps", Bindings.specs[1].modifier)
        Assert.Equal(0, Bindings.layerOrder.Length)
    }

    static Test_EmptyLayerListIsReported() {
        problems := Bindings_Tests.Load('{ "layers": ["1"], "bindings": [ { "keys": "F13", "action": "t.a", "layer": [] } ] }')
        Assert.Contains(problems[1], "empty list")
        Assert.Equal(0, Bindings.specs.Length)
    }

    static Test_RowsMarkOverriddenEveryLayerBindings() {
        Bindings_Tests.Load('{ "layers": ["1", "2"], "bindings": [',
            '{ "keys": "F13", "action": "t.a" },',
            '{ "keys": "F13", "action": "t.b", "layer": "2" } ] }')
        rows := Bindings.Rows()
        Assert.True(rows[1].onLayer && !rows[1].overridden, "not overridden on layer 1")
        Bindings.SetLayer("2")
        rows := Bindings.Rows()
        Assert.True(rows[1].overridden)
        Assert.False(rows[1].onLayer || rows[1].active)
        Assert.True(rows[2].onLayer && rows[2].active)
    }

    static Test_UnknownModifierIsReported() {
        problems := Bindings_Tests.Load('{ "bindings": [ { "keys": "F13", "modifier": "x", "action": "t.a" } ] }')
        Assert.Contains(problems[1], "unknown modifier 'x'")
    }

    static Join(list) {
        out := ""
        for i, v in list
            out .= (i = 1 ? "" : ",") v
        return out
    }
}
; Stands in for an InputHook in latch tests.
class FakeLatchHook {
    __New() {
        this.opts := Map()
        this.started := false
        this.stopped := false
        this.InProgress := false
        this.EndReason := ""
        this.EndKey := ""
        this.OnEnd := ""
        this.OnKeyUp := ""
    }
    KeyOpt(keys, opts) => this.opts[keys] := opts
    Start() => (this.started := true, this.InProgress := true)
    Stop() => (this.stopped := true, this.InProgress := false)
    Finish(reason, key) => (this.EndReason := reason, this.EndKey := key, this.InProgress := false)
}

TestRunner.Add(Bindings_Tests)
