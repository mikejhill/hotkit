#Requires AutoHotkey v2.0

; Declarative window recognition, so callers can describe windows in config
; instead of code. A spec is a Map; every present field must match:
;
;   exe              process name, e.g. "msedge.exe" (case-insensitive)
;   class            window class, exact
;   title            RegEx matched against the title
;   titleNotEmpty    true -> title must be non-empty
;   appUserModelId   exact AppUserModelID (identifies PWAs / packaged apps)
;   visible          true -> WS_VISIBLE style required
;   topLevel         true -> window must not be owned by another window
;   minWidth/minHeight  minimum size in pixels (ignored while minimized)
;
; Matches(spec, info) is pure (info is a plain object) and unit tested;
; Predicate(spec) returns a callable that reads live window state.
class WindowMatcher {
    static Fields := ["exe", "class", "title", "titleNotEmpty", "appUserModelId",
        "visible", "topLevel", "minWidth", "minHeight"]

    static Validate(spec) {
        if !(spec is Map)
            throw ValueError("Window match must be an object.")
        for key in spec {
            known := false
            for f in WindowMatcher.Fields {
                if (f = key) {
                    known := true
                    break
                }
            }
            if !known
                throw ValueError("Unknown window match field: " key)
        }
        return spec
    }

    static Matches(spec, info) {
        get := (k, d := "") => (spec.Has(k) ? spec[k] : d)
        if (spec.Has("exe") && info.exe != spec["exe"])
            return false
        if (spec.Has("class") && !(info.class == spec["class"]))
            return false
        if (spec.Has("title") && !RegExMatch(info.title, spec["title"]))
            return false
        if (get("titleNotEmpty", false) && info.title = "")
            return false
        if (get("visible", false) && !(info.style & 0x10000000))
            return false
        if (get("topLevel", false) && info.owner)
            return false
        if (!info.minimized) {
            if (info.width < get("minWidth", 0) || info.height < get("minHeight", 0))
                return false
        }
        if (spec.Has("appUserModelId") && info.aumid != spec["appUserModelId"])
            return false
        return true
    }

    static Predicate(spec) {
        WindowMatcher.Validate(spec)
        return (hwnd) => WindowMatcher.Matches(spec, WindowMatcher.Info(hwnd, spec.Has("appUserModelId")))
    }

    ; Snapshot of the properties Matches() reads.
    ; mutate: off (reads live window state)
    static Info(hwnd, withAumid := false) {
        WinGetPos(, , &w, &h, "ahk_id " hwnd)
        return {
            exe: WinGetProcessName("ahk_id " hwnd),
            class: WinGetClass("ahk_id " hwnd),
            title: WinGetTitle("ahk_id " hwnd),
            style: WinGetStyle("ahk_id " hwnd),
            owner: DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr"),
            minimized: WinGetMinMax("ahk_id " hwnd) = -1,
            width: w,
            height: h,
            aumid: withAumid ? WindowMatcher.AppUserModelId(hwnd) : "",
        }
    }

    static AppUserModelId(hwnd) {
        comResult := DllCall("ole32\CoInitialize", "ptr", 0, "int")
        try {
            iid := Buffer(16, 0)
            if DllCall("ole32\CLSIDFromString", "str", "{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}", "ptr", iid.Ptr, "int")
                return ""
            store := 0
            if DllCall("shell32\SHGetPropertyStoreForWindow", "ptr", hwnd, "ptr", iid.Ptr, "ptr*", &store, "int")
                return ""
            try {
                key := Buffer(20, 0)
                if DllCall("ole32\CLSIDFromString", "str", "{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}", "ptr", key.Ptr, "int")
                    return ""
                NumPut("uint", 5, key, 16)
                value := Buffer(24, 0)
                if ComCall(5, store, "ptr", key.Ptr, "ptr", value.Ptr, "int")
                    return ""
                try {
                    if (NumGet(value, 0, "ushort") != 31)
                        return ""
                    stringPtr := NumGet(value, 8, "ptr")
                    return stringPtr ? StrGet(stringPtr, "UTF-16") : ""
                } finally {
                    DllCall("ole32\PropVariantClear", "ptr", value.Ptr, "int")
                }
            } finally {
                ComCall(2, store, "uint")
            }
        } catch {
            return ""
        } finally {
            if (comResult >= 0)
                DllCall("ole32\CoUninitialize")
        }
    }
}
