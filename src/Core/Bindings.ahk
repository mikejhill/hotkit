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
;   layer        name of a layer from "layers" (active while its key is held)
;   group        name of a group that can be toggled on/off at runtime
;   whenActive   WinTitle; binding only fires while a matching window is active
;   description  shown in the shortcut overlay
;   enabled      false to skip
;
; Plan() validates without touching the system; Apply() registers hotkeys.
class Bindings {
    static specs := []
    static problems := []
    static layers := Bindings._CaseMap()
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
        Bindings.layers := Bindings._CaseMap()
        Bindings.groups := Bindings._CaseMap()
        Bindings._contexts := Bindings._CaseMap()
    }

    ; Loads layers, groups, and bindings from a Config. Returns problems found.
    static LoadConfig(cfg, source := "config") {
        for name, layer in cfg.Section("layers")
            Bindings.DefineLayer(name, layer)
        for name, group in cfg.Section("groups")
            Bindings.DefineGroup(name, MapGet(group, "enabled", true), MapGet(group, "description", ""))
        for index, raw in cfg.List("bindings")
            Bindings.Add(raw, source " #" index)
        return Bindings.problems
    }

    static DefineLayer(name, layer) {
        key := (layer is Map) ? MapGet(layer, "key", "") : String(layer)
        if (key = "") {
            Bindings.problems.Push("Layer '" name "' has no key.")
            return
        }
        label := (layer is Map) ? MapGet(layer, "label", key) : key
        Bindings.layers[name] := { name: name, key: key, label: label }
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
            layer: MapGet(raw, "layer", ""),
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
        if (spec.layer != "" && !Bindings.layers.Has(spec.layer)) {
            Bindings.problems.Push(source " (" keys "): unknown layer '" spec.layer "'.")
            return ""
        }
        if (spec.group != "" && !Bindings.groups.Has(spec.group))
            Bindings.DefineGroup(spec.group)
        if (spec.description = "")
            spec.description := Bindings._DefaultDescription(spec)
        Bindings.specs.Push(spec)
        return spec
    }

    ; Validates action ids and detects duplicate key assignments.
    static Validate() {
        seen := Bindings._CaseMap()
        for spec in Bindings.specs {
            for ref in Bindings._Refs(spec) {
                if !ActionRegistry.Has(ref.action)
                    Bindings.problems.Push(spec.source " (" spec.keys "): unknown action '" ref.action "'.")
            }
            id := Bindings.ContextKey(spec) "|" spec.keys
            if (seen.Has(id))
                Bindings.problems.Push("Conflict: '" spec.keys "' bound by " seen[id] " and " spec.source ".")
            else
                seen[id] := spec.source
        }
        return Bindings.problems
    }

    static ContextKey(spec) => spec.layer "|" spec.group "|" spec.whenActive

    ; Registers every spec as a live hotkey. Problems are collected, not thrown.
    static Apply() {
        for spec in Bindings.specs {
            try {
                Bindings._Register(spec)
            } catch as e {
                Bindings.problems.Push(spec.source " (" spec.keys "): " e.Message)
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
            label := spec.layer != "" ? Bindings.layers[spec.layer].label : ""
            rows.Push({
                keys: HotkeyText.Format(spec.keys, label),
                raw: spec.keys,
                description: spec.description,
                action: spec.kind = "gestures" ? "(gestures)" : spec.action,
                layer: spec.layer,
                group: spec.group,
                active: spec.group = "" || Bindings.GroupEnabled(spec.group),
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

    ; Returns a shared HotIf callback for a layer/group/window combination,
    ; or "" for global bindings.
    static _Context(spec) {
        id := Bindings.ContextKey(spec)
        if (id = "||")
            return ""
        if (Bindings._contexts.Has(id))
            return Bindings._contexts[id]
        layerKey := spec.layer != "" ? Bindings.layers[spec.layer].key : ""
        group := spec.group
        winTitle := spec.whenActive
        fn := (*) => (layerKey = "" || GetKeyState(layerKey, "P"))
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
