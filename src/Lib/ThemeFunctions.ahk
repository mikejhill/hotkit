#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\Debugger.ahk


; ======================================================================
; Windows light/dark theme toggle.
; Public API:
;   ThemeFunctions.ToggleTheme(timeoutMs := 2000, logPath := "")
;     - Toggles apps + system theme and broadcasts "ImmersiveColorSet".
;     - Returns Map("previous", 0|1, "current", 0|1, "broadcastOk", 0|1, "elapsedMs", n)
;       where 1 = light, 0 = dark.
; ======================================================================
class ThemeFunctions {
    ; ------------------------- Constants -----------------------------------
    static REG_PATH := "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    static REG_APPS := "AppsUseLightTheme"
    static REG_SYS := "SystemUsesLightTheme"

    ; ------------------------- Public API ----------------------------------
    static ToggleTheme(timeoutMs := 2000, logPath := "") {
        Debugger.Log("Starting theme toggle…", "INFO")

        ; Ensure current value (default 1=light if missing)
        ; Note: Windows which exist before the key is created may fail to handle changes
        ThemeFunctions._EnsureRegKeyExists(ThemeFunctions.REG_PATH)
        current := RegRead(ThemeFunctions.REG_PATH, ThemeFunctions.REG_APPS, 1)
        Debugger.Log("Current " ThemeFunctions.REG_APPS " = " current, "INFO")

        ; Toggle (0 <-> 1)
        newVal := 1 - current
        RegWrite(newVal, "REG_DWORD", ThemeFunctions.REG_PATH, ThemeFunctions.REG_APPS)
        RegWrite(newVal, "REG_DWORD", ThemeFunctions.REG_PATH, ThemeFunctions.REG_SYS)

        ; Verify writes
        appsNow := RegRead(ThemeFunctions.REG_PATH, ThemeFunctions.REG_APPS, newVal)
        sysNow := RegRead(ThemeFunctions.REG_PATH, ThemeFunctions.REG_SYS, newVal)
        Debugger.Log("Wrote " ThemeFunctions.REG_APPS "=" appsNow ", " ThemeFunctions.REG_SYS "=" sysNow, "INFO")

        ; Broadcast WM_SETTINGCHANGE / "ImmersiveColorSet"
        ; result := _BroadcastImmersiveColorSet(timeoutMs, logPath)
        result := ThemeFunctions._BroadcastImmersiveColorSet(logPath)

        Debugger.Log("Done.", "INFO")
        return Map("previous", current, "current", newVal, "broadcastOk", result.Get("ok"), "elapsedMs", result.Get(
            "elapsedMs"))
    }

    ; --------------------- Broadcast helper ---------------------------------
    static _BroadcastImmersiveColorSet(logPath := "") {
        ; _BroadcastImmersiveColorSet(timeoutMs := 2000, logPath := "") {
        ; HWND_BROADCAST=0xFFFF, WM_SETTINGCHANGE=0x001A, SMTO_ABORTIFHUNG=0x0002
        ; callResult := 0
        start := A_TickCount
        ; ok := DllCall(
        ;     "user32.dll\SendMessageTimeoutW",
        ;     "Ptr", 0xFFFF,              ; HWND_BROADCAST
        ;     "UInt", 0x001A,              ; WM_SETTINGCHANGE
        ;     "UPtr", 0,                   ; wParam
        ;     "Str", "ImmersiveColorSet", ; lParam
        ;     "UInt", 0x0002,              ; SMTO_ABORTIFHUNG
        ;     "UInt", timeoutMs,           ; timeout
        ;     "UPtrP", callResult,         ; lpdwResult
        ;     "UInt"                       ; return (non-zero = success)
        ; )
        ; Use asynchronous SendNotifyMessage to avoid errors where synchronous messaging conflicts with certain applications.
        ; Example synchronous messaging error (Windows Terminal): "An outgoing call cannot be made since the application is
        ; dispatching an input-synchronous call.
        ok := DllCall(
            "user32.dll\SendNotifyMessageW",
            "Ptr", 0xFFFF,              ; [in] hWnd; HWND_BROADCAST (0xFFFF): All top-level windows
            "UInt", 0x001A,              ; [in] Msg; WM_SETTINGCHANGE (0x001A): User-configurable system parameter has changed
            "UPtr", 0,                   ; [in] wParam; No additional info required for message
            "Str", "ImmersiveColorSet"  ; [in] lParam; Windows config theme change
        )
        elapsed := A_TickCount - start

        if (!ok) {
            ; Debugger.Log("SendMessageTimeoutW returned 0 (fail/timeout), lpdwResult=" callResult ", elapsed=" elapsed "ms", "WARN")
            Debugger.Log("SendMessageTimeoutW returned 0 (fail/timeout), elapsed=" elapsed "ms", "WARN")
            Debugger.Log("Some apps may not refresh automatically.", "WARN")
        } else {
            ; Debugger.Log("SendMessageTimeoutW succeeded (non-zero), lpdwResult=" callResult ", elapsed=" elapsed "ms", "INFO")
            Debugger.Log("SendMessageTimeoutW succeeded (non-zero), elapsed=" elapsed "ms", "INFO")
        }
        ; return Map("ok", ok, "elapsedMs", elapsed, "lpdw", callResult)
        return Map("ok", ok, "elapsedMs", elapsed)
    }

    ; --------------------- Registry helper ----------------------------------
    ; Creates a registry key if missing, without writing any values.
    ; Returns an object: { created: true/false, disposition: 1|2, code: Win32Error }
    ;   disposition = 1 (created) | 2 (opened existing)
    ; access defaults to KEY_READ | KEY_WRITE. You can OR with WOW64 flags if needed.
    static _EnsureRegKeyExists(keyPath, access := 0x20006, wow64 := "") {
        ; access default: KEY_READ (0x20019) | KEY_WRITE (0x20006) → we choose 0x20006 for write/open.
        ; Common extras:
        ;   KEY_WOW64_64KEY = 0x0100
        ;   KEY_WOW64_32KEY = 0x0200
        if !keyPath
            throw Error("keyPath is empty.")

        ; Normalize separators and trim whitespace/trailing slashes
        keyPath := StrReplace(Trim(keyPath), "/", "\")
        while SubStr(keyPath, -0) = "\"  ; strip trailing backslashes
            keyPath := SubStr(keyPath, 1, -1)

        ; Split into root token and subkey
        pos := InStr(keyPath, "\")
        if !pos
            throw Error("keyPath must include a hive and a subkey, e.g. HKCU\Software\...")

        rootToken := StrUpper(SubStr(keyPath, 1, pos - 1))
        subKey := SubStr(keyPath, pos + 1)

        if (subKey = "")
            throw Error("Path must include a subkey below the root.")

        ; Map root token to predefined HKEY handles
        static Hives := Map(
            "HKCR", 0x80000000, "HKEY_CLASSES_ROOT", 0x80000000,
            "HKCU", 0x80000001, "HKEY_CURRENT_USER", 0x80000001,
            "HKLM", 0x80000002, "HKEY_LOCAL_MACHINE", 0x80000002,
            "HKU", 0x80000003, "HKEY_USERS", 0x80000003,
            "HKCC", 0x80000005, "HKEY_CURRENT_CONFIG", 0x80000005
        )

        if !Hives.Has(rootToken)
            throw Error("Unsupported hive token: " rootToken)

        root := Hives[rootToken]

        hKey := 0, disposition := 0
        ; LONG RegCreateKeyExW(
        ;   HKEY, LPCWSTR, DWORD, LPWSTR, DWORD, REGSAM, LPSECURITY_ATTRIBUTES, PHKEY, LPDWORD)
        r := DllCall("Advapi32\RegCreateKeyExW"
            , "Ptr", root
            , "WStr", subKey
            , "UInt", 0          ; Reserved
            , "Ptr", 0          ; Class (unused)
            , "UInt", 0          ; Options (REG_OPTION_NON_VOLATILE)
            , "UInt", access     ; Desired access (e.g., KEY_WRITE | KEY_READ | WOW64 flags)
            , "Ptr", 0          ; Security attrs
            , "Ptr*", hKey
            , "UInt*", disposition
            , "UInt")            ; Return type
        if (r)
            throw Error(Format("RegCreateKeyExW failed with error 0x{:X}", r))

        DllCall("Advapi32\RegCloseKey", "Ptr", hKey)
        return disposition  ; 1 = created, 2 = opened existing
    }
}
