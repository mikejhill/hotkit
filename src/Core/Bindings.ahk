#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\ActionRegistry.ahk
#Include %A_LineFile%\..\..\Lib\HotkeyText.ahk
#Include %A_LineFile%\..\Config.ahk

; Turns binding definitions (from config or plugins) into live hotkeys.
;
; A binding is a Map with:
;   keys         AutoHotkey hotkey notation, e.g. ">^>!PgUp", "LShift & Volume_Up"
;   action/args  action id and positional arguments            (simple binding)
;   gestures     {tap, doubleTap, hold, holdMs, doubleTapMs}   (multi-gesture key)
;   onRelease    action reference run when the key (or the binding's modifier
;                key) is released (press-and-hold)
;   onNextKey    action reference run on the next press of any other key, which
;                is consumed (press, then latch until the next key)
;   onCancel     with onNextKey: run instead when that next key is Escape
;   exclusive    name shared by hold/latch bindings: while one is active,
;                pressing another stops it instead of starting
;   waitRelease  wait for the key to be released after the action runs
;   modifier     name of a held key from "modifiers" (active while it is held)
;   layer        layer name, or list of names, from "layers" (active only while
;                one of them is the active layer; omitted = every layer)
;   group        name of a group that can be toggled on/off at runtime
;   whenActive   WinTitle; binding only fires while a matching window is active
;   description  shown in the shortcut overlay
;   enabled      false to skip
;
; Plan() validates without touching the system; Apply() registers hotkeys.
class Bindings {
    static specs := []
    static problems := []
    static modifiers := Bindings._CaseMap()
    ; Switchable layers: exactly one is active at a time.
    static layers := Bindings._CaseMap()
    static layerOrder := []
    static activeLayer := ""
    static groups := Bindings._CaseMap()
    static _contexts := Bindings._CaseMap()
    static _registered := []
    ; exclusive name -> callback that stops the active hold/latch binding
    static _sessions := Bindings._CaseMap()
    ; Key that ended a latch: hold/latch starts are ignored until it is released,
    ; so stopping with a chord key doesn't immediately start again.
    static _rearmKey := ""
    static _latchStates := []
    ; Creates the InputHook a latch binding waits on (replaced in tests).
    static LatchHookFactory := (*) => InputHook("L0 I V")
    ; Keys that never end a latch (they pass through to the focused app).
    static LatchIgnoredKeys := "{LCtrl}{RCtrl}{LShift}{RShift}{LAlt}{RAlt}{LWin}{RWin}"

    static _CaseMap() {
        m := Map()
        m.CaseSense := "Off"
        return m
    }

    static Reset() {
        Bindings.UnregisterAll()
        Bindings.specs := []
        Bindings.problems := []
        Bindings.modifiers := Bindings._CaseMap()
        Bindings.layers := Bindings._CaseMap()
        Bindings.layerOrder := []
        Bindings.activeLayer := ""
        Bindings.groups := Bindings._CaseMap()
        Bindings._contexts := Bindings._CaseMap()
        Bindings._sessions := Bindings._CaseMap()
        Bindings._rearmKey := ""
    }

    ; Loads modifiers, layers, groups, and bindings from a Config. Returns
    ; problems found.
    static LoadConfig(cfg, source := "config") {
        for name, modifier in cfg.Section("modifiers")
            Bindings.DefineModifier(name, modifier)
        Bindings.DefineLayers(cfg.Get("layers", ""))
        for name, group in cfg.Section("groups")
            Bindings.DefineGroup(name, MapGet(group, "enabled", true), MapGet(group, "description", ""))
        for index, raw in cfg.List("bindings")
            Bindings.Add(raw, source " #" index)
        return Bindings.problems
    }

    static DefineModifier(name, modifier) {
        key := (modifier is Map) ? MapGet(modifier, "key", "") : String(modifier)
        if (key = "") {
            Bindings.problems.Push("Modifier '" name "' has no key.")
            return
        }
        label := (modifier is Map) ? MapGet(modifier, "label", key) : key
        titles := []
        raw := (modifier is Map) ? MapGet(modifier, "suspendWhenActive", []) : []
        for title in (raw is Array ? raw : [raw]) {
            if (title is String && Trim(title) != "")
                titles.Push(title)
            else
                Bindings.problems.Push("Modifier '" name "': suspendWhenActive entries must be non-empty WinTitle strings.")
        }
        Bindings.modifiers[name] := { name: name, key: key, label: label, suspendWhenActive: titles }
    }

    ; True when a window listed in the modifier's suspendWhenActive is active.
    ; Some windows (anti-keylogging protection) feed scrambled keystrokes to
    ; keyboard hooks, so modifier bindings would fire on random keys there.
    static ModifierSuspended(modifier) {
        for title in modifier.suspendWhenActive
            if WinActive(title)
                return true
        return false
    }

    ; "layers" is a list of names (["1", "2"]) or an object of name -> settings
    ; ({ "1": { "label": "Main", "default": true } }). Objects list in natural
    ; name order (2 before 10). The default layer is the one marked "default",
    ; else the first. An entry with a "key", or a plain key string, is a
    ; held-key modifier from before modifiers had their own section: it still
    ; works, and is reported.
    static DefineLayers(raw) {
        entries := []
        if (raw is Array) {
            for name in raw {
                if (!IsObject(name) && Trim(String(name)) != "")
                    entries.Push({ name: String(name), def: Map() })
                else
                    Bindings.problems.Push("layers: entries must be non-empty names.")
            }
        } else if (raw is Map) {
            for name, def in raw {
                ; A key as the whole value ("caps": "CapsLock") was shorthand too.
                if ((def is Map && def.Has("key")) || (!IsObject(def) && def != "")) {
                    Bindings.DefineModifier(name, def)
                    if !Bindings.modifiers.Has(name)
                        continue
                    Bindings.modifiers[name].legacy := true
                    Bindings.problems.Push("Layer '" name "' has a key: held keys are now modifiers. Move it to "
                        '"modifiers" and change "layer": "' name '" to "modifier": "' name '" in its bindings.')
                    continue
                }
                entries.Push({ name: String(name), def: def })
            }
            entries := Bindings.SortLayerEntries(entries)
        } else if (IsObject(raw) || raw != "") {
            Bindings.problems.Push("'layers' must be a list of names or an object.")
        }
        defaultName := ""
        for e in entries {
            if (Bindings.layers.Has(e.name)) {
                Bindings.problems.Push("Layer '" e.name "' is defined twice.")
                continue
            }
            def := e.def
            if !(def is Map) {
                Bindings.problems.Push("Layer '" e.name "': settings must be an object.")
                def := Map()
            }
            label := MapGet(def, "label", "")
            if (label = "")
                label := Bindings.DefaultLayerLabel(e.name)
            Bindings.layers[e.name] := { name: e.name, label: label, description: MapGet(def, "description", "") }
            Bindings.layerOrder.Push(e.name)
            if (MapGet(def, "default", false) && defaultName = "")
                defaultName := e.name
        }
        if (Bindings.layerOrder.Length)
            Bindings.activeLayer := defaultName != "" ? defaultName : Bindings.layerOrder[1]
    }

    ; Pure: "1" -> "Layer 1"; other names are their own label.
    static DefaultLayerLabel(name) => IsInteger(name) ? "Layer " name : name

    ; Pure: natural order: integer names numerically first, then the rest
    ; alphabetically (case-insensitive).
    static SortLayerEntries(entries) {
        out := []
        for e in entries {
            i := out.Length + 1
            while (i > 1 && Bindings._LayerNameLess(e.name, out[i - 1].name))
                i--
            out.InsertAt(i, e)
        }
        return out
    }

    static _LayerNameLess(a, b) {
        ai := IsInteger(a), bi := IsInteger(b)
        if (ai && bi)
            return Integer(a) < Integer(b)
        if (ai != bi)
            return ai
        return StrCompare(a, b) < 0
    }

    static LayerActive(name) => Bindings.activeLayer != "" && Bindings.activeLayer = name

    ; Makes a layer active. Returns its canonical name; throws for unknown names.
    static SetLayer(name) {
        name := String(name)
        if !Bindings.layers.Has(name)
            throw ValueError("Unknown layer: " name)
        Bindings.activeLayer := Bindings.layers[name].name
        return Bindings.activeLayer
    }

    ; Pure: the layer `step` places after `current` in `order`, wrapping around.
    static StepLayer(order, current, step) {
        if (!order.Length)
            return ""
        index := 0
        for i, name in order {
            if (name = current)
                index := i
        }
        if (!index)
            return order[1]
        return order[Mod(Mod(index - 1 + step, order.Length) + order.Length, order.Length) + 1]
    }

    static DefineGroup(name, enabled := true, description := "") {
        Bindings.groups[name] := { name: name, enabled: !!enabled, description: description }
    }

    ; Normalizes and validates one binding definition. Returns the spec or "".
    static Add(raw, source := "plugin") {
        if !(raw is Map) {
            Bindings.problems.Push(source ": binding must be an object.")
            return ""
        }
        if (raw.Has("enabled") && !raw["enabled"])
            return ""
        keys := Trim(MapGet(raw, "keys", ""))
        if (keys = "") {
            Bindings.problems.Push(source ": missing 'keys'.")
            return ""
        }
        spec := {
            keys: keys,
            source: source,
            description: MapGet(raw, "description", ""),
            modifier: Bindings._Name(MapGet(raw, "modifier", "")),
            layers: [],
            group: MapGet(raw, "group", ""),
            whenActive: MapGet(raw, "whenActive", ""),
            waitRelease: !!MapGet(raw, "waitRelease", false),
            exclusive: Bindings._Name(MapGet(raw, "exclusive", "")),
            kind: "action",
            action: "",
            args: [],
            gestures: "",
            onRelease: "",
            onNextKey: "",
            onCancel: "",
        }
        try {
            if (raw.Has("gestures")) {
                for name in ["onRelease", "onNextKey", "onCancel"] {
                    if raw.Has(name)
                        throw ValueError("'" name "' can't be combined with 'gestures'.")
                }
                spec.kind := "gestures"
                spec.gestures := Bindings._ParseGestures(raw["gestures"])
            } else {
                ref := ActionRegistry.ParseRef(raw)
                spec.action := ref.action
                spec.args := ref.args
                if (raw.Has("onRelease") && raw.Has("onNextKey"))
                    throw ValueError("use either 'onRelease' or 'onNextKey', not both.")
                if (raw.Has("onCancel") && !raw.Has("onNextKey"))
                    throw ValueError("'onCancel' needs 'onNextKey'.")
                if (raw.Has("onRelease")) {
                    spec.kind := "hold"
                    spec.onRelease := ActionRegistry.ParseRef(raw["onRelease"])
                } else if (raw.Has("onNextKey")) {
                    spec.kind := "latch"
                    spec.onNextKey := ActionRegistry.ParseRef(raw["onNextKey"])
                    if raw.Has("onCancel")
                        spec.onCancel := ActionRegistry.ParseRef(raw["onCancel"])
                }
            }
            if (spec.exclusive != "" && spec.kind != "hold" && spec.kind != "latch")
                throw ValueError("'exclusive' needs 'onRelease' or 'onNextKey'.")
            if (spec.kind = "latch" && HotkeyText.Parse(keys).up)
                throw ValueError("'onNextKey' needs a key-down hotkey, not UP.")
        } catch as e {
            Bindings.problems.Push(source " (" keys "): " e.Message)
            return ""
        }
        rawLayer := MapGet(raw, "layer", "")
        ; Bindings written before modifiers had their own section.
        if (rawLayer is String && spec.modifier = "" && Bindings.modifiers.Has(rawLayer)
            && Bindings.modifiers[rawLayer].HasOwnProp("legacy") && !Bindings.layers.Has(rawLayer)) {
            spec.modifier := rawLayer
            rawLayer := ""
        }
        if (spec.modifier != "" && !Bindings.modifiers.Has(spec.modifier)) {
            Bindings.problems.Push(source " (" keys "): unknown modifier '" spec.modifier "'.")
            return ""
        }
        if (rawLayer is Array && !rawLayer.Length) {
            Bindings.problems.Push(source " (" keys "): 'layer' is an empty list; omit it to bind on every layer.")
            return ""
        }
        for name in (rawLayer is Array ? rawLayer : (IsObject(rawLayer) || rawLayer != "" ? [rawLayer] : [])) {
            if (IsObject(name) || !Bindings.layers.Has(String(name))) {
                Bindings.problems.Push(source " (" keys "): unknown layer '" (IsObject(name) ? "{…}" : name) "'.")
                return ""
            }
            canonical := Bindings.layers[String(name)].name
            if !Bindings._Includes(spec.layers, canonical)
                spec.layers.Push(canonical)
        }
        if (spec.group != "" && !Bindings.groups.Has(spec.group))
            Bindings.DefineGroup(spec.group)
        if (spec.description = "")
            spec.description := Bindings._DefaultDescription(spec)
        Bindings.specs.Push(spec)
        return spec
    }

    ; Validates action ids and detects duplicate key assignments. Bindings on
    ; the same keys conflict when their layers overlap; one limited to layers
    ; and one on every layer don't: the layer binding wins on its layers.
    static Validate() {
        seen := Bindings._CaseMap()
        for spec in Bindings.specs {
            for ref in Bindings._Refs(spec) {
                if !ActionRegistry.Has(ref.action)
                    Bindings.problems.Push(spec.source " (" spec.keys "): unknown action '" ref.action "'.")
            }
            id := spec.modifier "|" spec.group "|" spec.whenActive "|" spec.keys
            if !seen.Has(id)
                seen[id] := []
            for prev in seen[id] {
                if Bindings.LayersOverlap(prev.layers, spec.layers) {
                    Bindings.problems.Push("Conflict: '" spec.keys "' bound by " prev.source " and " spec.source ".")
                    break
                }
            }
            seen[id].Push(spec)
        }
        return Bindings.problems
    }

    ; Pure: whether two bindings' layer lists can be live at the same time
    ; (an empty list means every layer, and is overridden by a non-empty one).
    static LayersOverlap(a, b) {
        if (!a.Length || !b.Length)
            return !a.Length && !b.Length
        for x in a {
            if Bindings._Includes(b, x)
                return true
        }
        return false
    }

    ; Layer names may contain any character, so each is length-prefixed.
    static ContextKey(spec) {
        layerText := ""
        for name in spec.layers
            layerText .= StrLen(name) ":" name
        return spec.modifier "|" layerText "|" spec.group "|" spec.whenActive
    }

    ; Registers every spec as a live hotkey. Problems are collected, not thrown.
    ; Layer bindings go first: when several variants of a hotkey are eligible,
    ; AutoHotkey runs the one created earliest, so a layer binding overrides an
    ; every-layer binding on the same keys.
    static Apply() {
        for layered in [true, false] {
            for spec in Bindings.specs {
                if ((spec.layers.Length > 0) != layered)
                    continue
                try {
                    Bindings._Register(spec)
                } catch as e {
                    Bindings.problems.Push(spec.source " (" spec.keys "): " e.Message)
                }
            }
        }
        return Bindings.problems
    }

    static UnregisterAll() {
        for entry in Bindings._registered {
            try {
                HotIf(entry.context)
                Hotkey(entry.keys, "Off")
            }
        }
        try HotIf()
        Bindings._registered := []
        ; Stop waiting latches without running their actions.
        for state in Bindings._latchStates {
            if (state.hook != "")
                try state.hook.Stop()
        }
        Bindings._latchStates := []
    }

    static GroupEnabled(name) => Bindings.groups.Has(name) && Bindings.groups[name].enabled

    static SetGroup(name, enabled) {
        if !Bindings.groups.Has(name)
            throw ValueError("Unknown binding group: " name)
        Bindings.groups[name].enabled := !!enabled
        return Bindings.groups[name].enabled
    }

    static ToggleGroup(name) => Bindings.SetGroup(name, !Bindings.GroupEnabled(name))

    ; Display rows for the shortcut overlay.
    ; An every-layer binding is "overridden" (and not onLayer) while a binding on
    ; the active layer has the same keys, modifier, group and whenActive.
    static Rows() {
        rows := []
        shadowed := Bindings._CaseMap()
        for spec in Bindings.specs {
            if (spec.layers.Length && Bindings._Includes(spec.layers, Bindings.activeLayer))
                shadowed[spec.modifier "|" spec.group "|" spec.whenActive "|" spec.keys] := true
        }
        for spec in Bindings.specs {
            label := spec.modifier != "" ? Bindings.modifiers[spec.modifier].label : ""
            layerText := ""
            for i, name in spec.layers
                layerText .= (i = 1 ? "" : ", ") Bindings.layers[name].label
            overridden := !spec.layers.Length && shadowed.Has(spec.modifier "|" spec.group "|" spec.whenActive "|" spec.keys)
            onLayer := (!spec.layers.Length && !overridden) || Bindings._Includes(spec.layers, Bindings.activeLayer)
            rows.Push({
                keys: HotkeyText.Format(spec.keys, label),
                raw: spec.keys,
                description: spec.description,
                action: spec.kind = "gestures" ? "(gestures)" : spec.action,
                modifier: spec.modifier,
                layers: layerText,
                onLayer: onLayer,
                overridden: overridden,
                group: spec.group,
                active: onLayer && (spec.group = "" || Bindings.GroupEnabled(spec.group)),
                source: spec.source,
            })
        }
        return rows
    }

    ; ---------------- Internals                    ------------------------------

    ; mutate: off (hotkey registration and key-state handlers; covered by e2e)
    static _Register(spec) {
        context := Bindings._Context(spec)
        handler := Bindings._Handler(spec)
        HotIf(context)
        try {
            Hotkey(spec.keys, handler, "On")
            Bindings._registered.Push({ keys: spec.keys, context: context })
            if (spec.kind = "hold")
                Bindings._RegisterRelease(spec)
            else if (spec.kind = "latch")
                Bindings._RegisterLatchKeys(spec)
        } finally {
            HotIf()
        }
    }

    ; Returns a shared HotIf callback for a modifier/layer/group/window
    ; combination, or "" for global bindings.
    static _Context(spec) {
        id := Bindings.ContextKey(spec)
        if (id = "|||")
            return ""
        if (Bindings._contexts.Has(id))
            return Bindings._contexts[id]
        modifier := spec.modifier != "" ? Bindings.modifiers[spec.modifier] : ""
        modifierKey := modifier ? modifier.key : ""
        layerNames := spec.layers
        group := spec.group
        winTitle := spec.whenActive
        fn := (*) => (modifierKey = "" || (GetKeyState(modifierKey, "P") && !Bindings.ModifierSuspended(modifier)))
            && (!layerNames.Length || Bindings._Includes(layerNames, Bindings.activeLayer))
            && (group = "" || Bindings.GroupEnabled(group))
            && (winTitle = "" || WinActive(winTitle))
        Bindings._contexts[id] := fn
        return fn
    }

    static _Handler(spec) {
        switch spec.kind {
            case "gestures":
                return Bindings._GestureHandler(spec)
            case "hold":
                return Bindings._HoldHandler(spec)
            case "latch":
                return Bindings._LatchHandler(spec)
        }
        action := spec.action
        args := spec.args
        if (spec.waitRelease) {
            base := HotkeyText.BaseKey(spec.keys)
            return (*) => (ActionRegistry.SafeInvoke(action, args), KeyWait(base))
        }
        return (*) => ActionRegistry.SafeInvoke(action, args)
    }

    ; Press runs the action once; repeats are swallowed. Releasing the key or
    ; the binding's modifier key, whichever comes first, runs onRelease.
    static _HoldHandler(spec) {
        state := Bindings.NewKeyState()
        spec.holdState := state
        return (*) => Bindings.HoldPress(spec, state)
    }

    static _RegisterRelease(spec) {
        state := spec.holdState
        base := HotkeyText.BaseKey(spec.keys)
        downContext := (*) => state.baseDown
        HotIf(downContext)
        ; Swallow auto-repeat until the key is let go, even after the hold
        ; ended or the modifier key was let go first.
        Bindings._On("*" base, (*) => 0, downContext)
        Bindings._On("~*" base " Up", (*) => (state.baseDown := false, Bindings.HoldEnd(spec, state)), downContext)
        modifierKey := Bindings.ModifierKey(spec)
        if (modifierKey != "") {
            heldContext := (*) => state.active
            HotIf(heldContext)
            Bindings._On("~*" modifierKey " Up", (*) => Bindings.HoldEnd(spec, state), heldContext)
        }
    }

    ; Press runs the action and waits for the next press of another key (see
    ; LatchHookFactory), which is consumed and runs onNextKey (or onCancel for
    ; Escape). Keys still held from the chord don't count until released.
    static _LatchHandler(spec) {
        state := Bindings.NewKeyState()
        spec.latchState := state
        Bindings._latchStates.Push(state)
        return (*) => Bindings.LatchPress(spec, state)
    }

    static _RegisterLatchKeys(spec) {
        state := spec.latchState
        base := HotkeyText.BaseKey(spec.keys)
        downContext := (*) => state.baseDown
        HotIf(downContext)
        Bindings._On("*" base, (*) => 0, downContext)
        Bindings._On("~*" base " Up", (*) => (state.baseDown := false, Bindings.LatchKeyReleased(state, base)), downContext)
        modifierKey := Bindings.ModifierKey(spec)
        if (modifierKey != "" && modifierKey != base) {
            pendingContext := (*) => state.pending.Has(modifierKey)
            HotIf(pendingContext)
            Bindings._On("~*" modifierKey " Up", (*) => Bindings.LatchKeyReleased(state, modifierKey), pendingContext)
        }
    }

    static _On(keys, callback, context) {
        Hotkey(keys, callback, "On")
        Bindings._registered.Push({ keys: keys, context: context })
    }

    static _StartLatchHook(spec, state) {
        ih := Bindings.LatchHookFactory.Call()
        ih.KeyOpt("{All}", "ES")
        ih.KeyOpt(Bindings.LatchIgnoredKeys, "-ES")
        for key in state.pending
            ih.KeyOpt(Bindings.KeyOptKeys(key), "-ES")
        ih.OnEnd := (hook) => Bindings.LatchHookEnded(spec, state, hook)
        state.hook := ih
        ih.Start()
    }

    ; True when a key that ended a latch is still physically down.
    static _RearmPending() {
        if (Bindings._rearmKey = "")
            return false
        if GetKeyState(Bindings._rearmKey, "P")
            return true
        Bindings._rearmKey := ""
        return false
    }

    ; Tap / double-tap / hold on one key. Hold is detected with KeyWait.
    static _GestureHandler(spec) {
        g := spec.gestures
        base := HotkeyText.BaseKey(spec.keys)
        state := { lastTap: 0 }
        return (*) => Bindings._Gesture(g, base, state)
    }

    static _Gesture(g, base, state) {
        if (g.hold != "" && !KeyWait(base, "T" (g.holdMs / 1000))) {
            state.lastTap := 0
            ActionRegistry.SafeInvoke(g.hold.action, g.hold.args)
            KeyWait(base)
            return
        }
        if (g.doubleTap = "") {
            if (g.tap != "")
                ActionRegistry.SafeInvoke(g.tap.action, g.tap.args)
            return
        }
        now := A_TickCount
        if (state.lastTap && now - state.lastTap <= g.doubleTapMs) {
            state.lastTap := 0
            ActionRegistry.SafeInvoke(g.doubleTap.action, g.doubleTap.args)
            return
        }
        state.lastTap := now
        tick := now
        SetTimer(() => Bindings._GestureSingle(g, state, tick), -g.doubleTapMs)
    }

    static _GestureSingle(g, state, tick) {
        if (state.lastTap != tick)
            return
        state.lastTap := 0
        if (g.tap != "")
            ActionRegistry.SafeInvoke(g.tap.action, g.tap.args)
    }

    ; mutate: on

    ; ---------------- Hold and latch state      ------------------------------
    ; Driven by the hotkeys above; callable directly from tests.

    static NewKeyState() => { active: false, baseDown: false, pending: Bindings._CaseMap(), hook: "" }

    ; The key of the binding's modifier, or "".
    static ModifierKey(spec) {
        if (spec.modifier = "" || !Bindings.modifiers.Has(spec.modifier))
            return ""
        return Bindings.modifiers[spec.modifier].key
    }

    static HoldPress(spec, state) {
        if (state.baseDown)
            return
        state.baseDown := true
        if Bindings._Preempted(spec)
            return
        state.active := true
        Bindings._Begin(spec, () => Bindings.HoldEnd(spec, state))
        ActionRegistry.SafeInvoke(spec.action, spec.args)
    }

    static HoldEnd(spec, state) {
        if (!state.active)
            return
        state.active := false
        Bindings._Finish(spec)
        ActionRegistry.SafeInvoke(spec.onRelease.action, spec.onRelease.args)
    }

    static LatchPress(spec, state) {
        if (state.baseDown)
            return
        state.baseDown := true
        if (state.active) {
            Bindings.LatchEnd(spec, state, spec.onNextKey)
            return
        }
        if Bindings._Preempted(spec)
            return
        state.active := true
        state.pending := Bindings._CaseMap()
        state.pending[HotkeyText.BaseKey(spec.keys)] := true
        modifierKey := Bindings.ModifierKey(spec)
        if (modifierKey != "")
            state.pending[modifierKey] := true
        Bindings._Begin(spec, () => Bindings.LatchEnd(spec, state, spec.onNextKey))
        Bindings._StartLatchHook(spec, state)
        ActionRegistry.SafeInvoke(spec.action, spec.args)
    }

    ; A key held since the chord was let go: its next press ends the latch.
    static LatchKeyReleased(state, key) {
        if !state.pending.Has(key)
            return
        state.pending.Delete(key)
        if (state.hook != "" && state.hook.InProgress)
            state.hook.KeyOpt(Bindings.KeyOptKeys(key), "+ES")
    }

    static LatchHookEnded(spec, state, hook) {
        if (hook != state.hook)
            return
        state.hook := ""
        if (hook.EndReason != "EndKey")
            return
        Bindings.LatchEnd(spec, state, Bindings.LatchStopRef(spec, hook.EndKey), hook.EndKey)
    }

    ; Ends an active latch with `ref`. `endKey` is the key that ended it, if any.
    static LatchEnd(spec, state, ref, endKey := "") {
        if (!state.active)
            return
        state.active := false
        state.pending := Bindings._CaseMap()
        if (state.hook != "") {
            hook := state.hook
            state.hook := ""
            try hook.Stop()
        }
        Bindings._Finish(spec)
        if (endKey != "")
            Bindings._rearmKey := endKey
        ActionRegistry.SafeInvoke(ref.action, ref.args)
    }

    ; A key for InputHook.KeyOpt by both virtual key and scan code: "{All}"
    ; sets both tables, and an option cleared in one is still set in the other.
    static KeyOptKeys(key) {
        vk := GetKeyVK(key), sc := GetKeySC(key)
        out := vk ? Format("{{}vk{:X}{}}", vk) : ""
        out .= sc ? Format("{{}sc{:X}{}}", sc) : ""
        return out != "" ? out : "{" key "}"
    }

    ; Pure: the reference a latch runs when `endKey` ends it.
    static LatchStopRef(spec, endKey) {
        if (spec.onCancel != "" && (endKey = "Escape" || endKey = "Esc"))
            return spec.onCancel
        return spec.onNextKey
    }

    ; True when a hold/latch press must not start: a key that ended a latch is
    ; still down, or another binding with the same `exclusive` name is active
    ; (that one is stopped instead).
    static _Preempted(spec) {
        if Bindings._RearmPending()
            return true
        if (spec.exclusive != "" && Bindings._sessions.Has(spec.exclusive)) {
            Bindings._sessions[spec.exclusive].stop.Call()
            return true
        }
        return false
    }

    static _Begin(spec, stop) {
        if (spec.exclusive != "")
            Bindings._sessions[spec.exclusive] := { spec: spec, stop: stop }
    }

    static _Finish(spec) {
        if (spec.exclusive != "" && Bindings._sessions.Has(spec.exclusive)
            && Bindings._sessions[spec.exclusive].spec = spec)
            Bindings._sessions.Delete(spec.exclusive)
    }

    static _ParseGestures(raw) {
        if !(raw is Map)
            throw ValueError("'gestures' must be an object.")
        g := {
            tap: raw.Has("tap") ? ActionRegistry.ParseRef(raw["tap"]) : "",
            doubleTap: raw.Has("doubleTap") ? ActionRegistry.ParseRef(raw["doubleTap"]) : "",
            hold: raw.Has("hold") ? ActionRegistry.ParseRef(raw["hold"]) : "",
            holdMs: MapGet(raw, "holdMs", 500),
            doubleTapMs: MapGet(raw, "doubleTapMs", 250),
        }
        if (g.tap = "" && g.doubleTap = "" && g.hold = "")
            throw ValueError("'gestures' needs at least one of tap, doubleTap, hold.")
        return g
    }

    ; A name read from config, as text ("{…}" for objects, which match nothing).
    static _Name(value) => IsObject(value) ? "{…}" : String(value)

    static _Includes(list, value) {
        for item in list {
            if (item = value)
                return true
        }
        return false
    }

    static _Refs(spec) {
        refs := []
        if (spec.kind = "gestures") {
            for name in ["tap", "doubleTap", "hold"] {
                if (spec.gestures.%name% != "")
                    refs.Push(spec.gestures.%name%)
            }
            return refs
        }
        refs.Push({ action: spec.action, args: spec.args })
        for ref in [spec.onRelease, spec.onNextKey, spec.onCancel] {
            if (ref != "")
                refs.Push(ref)
        }
        return refs
    }

    static _DefaultDescription(spec) {
        if (spec.kind = "gestures") {
            parts := []
            for name in ["tap", "doubleTap", "hold"] {
                if (spec.gestures.%name% != "")
                    parts.Push(name ": " spec.gestures.%name%.action)
            }
            out := ""
            for i, p in parts
                out .= (i = 1 ? "" : ", ") p
            return out
        }
        desc := ""
        if ActionRegistry.Has(spec.action)
            desc := ActionRegistry.Get(spec.action).description
        if (desc = "")
            desc := spec.action
        if (spec.args.Length) {
            argText := ""
            for i, a in spec.args
                argText .= (i = 1 ? "" : ", ") (IsObject(a) ? "{…}" : a)
            desc .= " (" argText ")"
        }
        return desc
    }
}
