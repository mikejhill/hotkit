#Requires AutoHotkey v2.0

; Named, discoverable commands. Modules and plugins register actions; bindings,
; tray items, and other actions refer to them by id.
;
;   ActionRegistry.Register("media.next", (*) => Send("{Media_Next}"),
;       { description: "Next track", module: "media" })
;   ActionRegistry.Invoke("media.next")
;   ActionRegistry.Invoke("app.toggle", ["notes"])
;
; Handlers receive the binding's "args" array spread as positional parameters.
class ActionRegistry {
    static _actions := ActionRegistry._NewMap()
    ; Called with (id, error) when a handler throws; defaults to a toast.
    static OnError := ""

    static _NewMap() {
        m := Map()
        m.CaseSense := "Off"
        return m
    }

    static Register(id, handler, meta := unset) {
        if !RegExMatch(id, "^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9]*)*$")
            throw ValueError("Invalid action id: " id)
        if !HasMethod(handler)
            throw TypeError("Action handler for '" id "' is not callable.")
        info := {
            id: id,
            handler: handler,
            description: "",
            module: "",
            params: "",
        }
        if (IsSet(meta)) {
            for k, v in meta.OwnProps()
                info.%k% := v
        }
        ActionRegistry._actions[id] := info
        return info
    }

    static Unregister(id) {
        if ActionRegistry._actions.Has(id)
            ActionRegistry._actions.Delete(id)
    }

    static Has(id) => ActionRegistry._actions.Has(id)

    static Get(id) {
        if !ActionRegistry._actions.Has(id)
            throw ValueError("Unknown action: " id)
        return ActionRegistry._actions[id]
    }

    ; Returns registered actions sorted by id.
    static List() {
        ids := []
        for id in ActionRegistry._actions
            ids.Push(id)
        ids := ActionRegistry._Sort(ids)
        out := []
        for id in ids
            out.Push(ActionRegistry._actions[id])
        return out
    }

    static Invoke(id, args := unset) {
        info := ActionRegistry.Get(id)
        params := IsSet(args) ? (args is Array ? args : [args]) : []
        return info.handler.Call(params*)
    }

    ; Invokes and reports failures instead of throwing (used by hotkeys/menus).
    static SafeInvoke(id, args := unset) {
        try {
            return ActionRegistry.Invoke(id, args?)
        } catch as e {
            if HasMethod(ActionRegistry.OnError)
                ActionRegistry.OnError.Call(id, e)
            else
                ActionRegistry._DefaultOnError(id, e)
        }
    }

    ; Builds a zero-argument callback for an action reference.
    ; A reference is either "action.id" or a Map {action, args}.
    static Callback(ref) {
        spec := ActionRegistry.ParseRef(ref)
        return (*) => ActionRegistry.SafeInvoke(spec.action, spec.args)
    }

    static ParseRef(ref) {
        if (Type(ref) = "String")
            return { action: ref, args: [] }
        if (ref is Map && ref.Has("action")) {
            args := ref.Has("args") ? ref["args"] : []
            return { action: ref["action"], args: args is Array ? args : [args] }
        }
        throw ValueError("Action reference must be a string or an object with an 'action' field.")
    }

    static Clear() {
        ActionRegistry._actions := ActionRegistry._NewMap()
    }

    static _DefaultOnError(id, e) {
        try Debugger.Log("Action '" id "' failed: " e.Message, "ERROR")
        try Toast.ShowToast({ color: "Red", fadeDelay: 5000 }, "Action failed: " id, e.Message)
    }

    static _Sort(items) {
        text := ""
        for item in items
            text .= item "`n"
        sorted := Sort(RTrim(text, "`n"))
        return sorted = "" ? [] : StrSplit(sorted, "`n")
    }
}
