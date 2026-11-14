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
;   onRelease    action reference run when the key is released (press-and-hold)
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
    ; else the first. An entry with a "key" is a held-key modifier from before
    ; modifiers had their own section: it still works, and is reported.
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
                if (def is Map && def.Has("key")) {
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
            kind: "action",
            action: "",
            args: [],
            gestures: "",
            onRelease: "",
        }
        try {
            if (raw.Has("gestures")) {
                spec.kind := "gestures"
                spec.gestures := Bindings._ParseGestures(raw["gestures"])
            } else {
                ref := ActionRegistry.ParseRef(raw)
                spec.action := ref.action
                spec.args := ref.args
                if (raw.Has("onRelease")) {
                    spec.kind := "hold"
                    spec.onRelease := ActionRegistry.ParseRef(raw["onRelease"])
                }
            }
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
    static Rows() {
        rows := []
        for spec in Bindings.specs {
            label := spec.modifier != "" ? Bindings.modifiers[spec.modifier].label : ""
            layerText := ""
            for i, name in spec.layers
                layerText .= (i = 1 ? "" : ", ") Bindings.layers[name].label
            onLayer := !spec.layers.Length || Bindings._Includes(spec.layers, Bindings.activeLayer)
            rows.Push({
                keys: HotkeyText.Format(spec.keys, label),
                raw: spec.keys,
                description: spec.description,
                action: spec.kind = "gestures" ? "(gestures)" : spec.action,
                modifier: spec.modifier,
                layers: layerText,
                onLayer: onLayer,
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
        }
        action := spec.action
        args := spec.args
        if (spec.waitRelease) {
            base := HotkeyText.BaseKey(spec.keys)
            return (*) => (ActionRegistry.SafeInvoke(action, args), KeyWait(base))
        }
        return (*) => ActionRegistry.SafeInvoke(action, args)
    }

    ; Press runs the action once; repeats are swallowed; release runs onRelease.
    static _HoldHandler(spec) {
        state := { held: false }
        spec.holdState := state
        action := spec.action
        args := spec.args
        return (*) => Bindings._HoldPress(state, action, args)
    }

    static _HoldPress(state, action, args) {
        if (state.held)
            return
        state.held := true
        ActionRegistry.SafeInvoke(action, args)
    }

    static _RegisterRelease(spec) {
        state := spec.holdState
        base := HotkeyText.BaseKey(spec.keys)
        release := spec.onRelease
        heldContext := (*) => state.held
        HotIf(heldContext)
        ; Swallow auto-repeat while held, even if the layer key was let go first.
        Hotkey("*" base, (*) => 0, "On")
        Hotkey("~*" base " Up", (*) => (state.held := false, ActionRegistry.SafeInvoke(release.action, release.args)), "On")
        Bindings._registered.Push({ keys: "*" base, context: heldContext })
        Bindings._registered.Push({ keys: "~*" base " Up", context: heldContext })
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
        if (spec.kind = "hold")
            refs.Push(spec.onRelease)
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
