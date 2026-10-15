#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\Toast.ahk
#Include %A_LineFile%\..\DDCCI.ahk
#Include %A_LineFile%\..\WmiBrightness.ahk

; ==============================================================================
; Display brightness: hardware (WMI laptop panels + DDC/CI external monitors),
; software gamma ramps, and Windows Night Light.
;
;   HardwareBrightness.Adjust(10)      ; all panels/monitors, +10
;   HardwareBrightness.Swap(0)         ; toggle between 0 and last level
;   GammaBrightness.Step(+1)           ; 2.5% steps below 100%, 5% above
;   NightLight.Toggle()
;
; Gamma: brightness < 100% -> gamma > 1 (darker); > 100% -> gamma < 1 (brighter).
; ==============================================================================


; ---------------- Hardware brightness            ------------------------------

class HardwareBrightness {
    static LastSelected := 50
    static SwapFallback := 85

    ; mutate: off (Win32/WMI/registry I/O)
    static Targets() {
        wmi := WmiBrightnessController.Initialize()
        wmi.RefreshMonitors()
        ddc := DDCCIController.Initialize()
        wmiKeys := wmi.GetIdKeys()
        ; Panels reachable through WMI are skipped on the DDC path.
        ddcTargets := []
        for entry in ddc.monitorEntries {
            if (entry.idKey = "" || !wmiKeys.Has(entry.idKey))
                ddcTargets.Push(entry)
        }
        return { wmi: wmi, ddc: ddc, ddcTargets: ddcTargets,
            any: wmi.monitors.Length > 0 || ddcTargets.Length > 0 }
    }

    static Current(targets) {
        if (targets.wmi.monitors.Length > 0)
            return targets.wmi.GetPrimaryBrightness()
        if (targets.ddcTargets.Length > 0)
            return targets.ddc.GetVCPFeature(targets.ddcTargets[1].hPhysical, 0x10).current
        return -1
    }

    static Adjust(delta) {
        t := HardwareBrightness.Targets()
        wmiResult := t.wmi.AdjustBrightness(delta, 1, false)
        ddcResult := t.ddc.AdjustMonitors(0x10, delta, t.ddcTargets, false)
        value := wmiResult.success > 0 ? wmiResult.value : ddcResult.value
        HardwareBrightness._Toast(delta, value, wmiResult.success + ddcResult.success, t.any)
    }

    static Set(value) {
        t := HardwareBrightness.Targets()
        wmiResult := t.wmi.SetAllMonitors(value, 1, false)
        ddcResult := t.ddc.SetMonitors(0x10, value, t.ddcTargets, false)
        HardwareBrightness._Toast(0, value, wmiResult.success + ddcResult.success, t.any)
    }

    ; Toggle between `target` and the last level that was neither 0 nor 100.
    static Swap(target) {
        t := HardwareBrightness.Targets()
        if (!t.any)
            return HardwareBrightness._Warn("No monitors found")
        current := HardwareBrightness.Current(t)
        if (current < 0)
            return HardwareBrightness._Warn("Brightness read failed")
        next := HardwareBrightness.SwapTarget(current, target)
        wmiResult := t.wmi.SetAllMonitors(next, 1, false)
        ddcResult := t.ddc.SetMonitors(0x10, next, t.ddcTargets, false)
        HardwareBrightness._Toast(0, next, wmiResult.success + ddcResult.success, t.any)
    }

    ; mutate: on
    ; Pure: decides the swap destination and remembers the user's level.
    static SwapTarget(current, target) {
        if (current = target) {
            last := HardwareBrightness.LastSelected
            return last = target ? HardwareBrightness.SwapFallback : last
        }
        if (current != 0 && current != 100)
            HardwareBrightness.LastSelected := current
        return target
    }

    ; mutate: off (Win32/WMI/registry I/O)
    static _Toast(delta, value, successCount, hasTargets) {
        if (!hasTargets)
            return HardwareBrightness._Warn("No monitors found")
        if (successCount <= 0)
            return HardwareBrightness._Warn(delta = 0 ? "Brightness set failed" : "Brightness adjust failed")
        icon := delta > 0 ? "🔆" : (delta < 0 ? "🔅" : "✓")
        text := value >= 0 ? "Brightness " value : "Brightness updated"
        Toast.ShowToast({ fadeDelay: 800 }, { text: icon, size: 24 }, { text: text, size: 14 })
    }

    static _Warn(text) {
        Toast.ShowToast({ fadeDelay: 1000 }, { text: "⚠", size: 24 }, { text: text, size: 14 })
    }
}


; ---------------- Gamma brightness               ------------------------------

class GammaBrightness {
    static Level := 100.0
    static Active := false
    static Min := 25.0
    static Max := 300.0
    static Saved := 85.0
    static DefaultSaved := 85.0

    ; mutate: on
    ; Pure: brightness percent -> gamma exponent.
    static GammaFor(percent) {
        if (percent = 100.0)
            return 1.0
        if (percent < 100.0)
            return 1.0 + ((100.0 - percent) / 100.0 * 2.0)
        return 1.0 - ((percent - 100.0) / 100.0 * 0.4)
    }

    ; Pure: next level for one step up (+1) or down (-1).
    ; Steps are 2.5% below 100% and 5% at or above it.
    static NextLevel(level, direction, minLevel := 25.0, maxLevel := 300.0) {
        if (direction > 0) {
            if (level >= maxLevel)
                return level
            step := level < 100.0 ? 2.5 : 5.0
            next := Ceil(level / step) * step
            if (next <= level)
                next := level + step
            return Min(maxLevel, next)
        }
        if (level <= minLevel)
            return level
        step := level <= 100.0 ? 2.5 : 5.0
        next := Floor(level / step) * step
        if (next >= level)
            next := level - step
        return Max(minLevel, next)
    }

    ; mutate: off (Win32/WMI/registry I/O)
    static Step(direction) {
        next := GammaBrightness.NextLevel(GammaBrightness.Level, direction, GammaBrightness.Min, GammaBrightness.Max)
        if (next != GammaBrightness.Level)
            GammaBrightness.Set(next)
    }

    static Set(value) {
        GammaBrightness.Level := Max(GammaBrightness.Min, Min(GammaBrightness.Max, value))
        GammaBrightness.Saved := GammaBrightness.Level
        GammaBrightness.Active := GammaBrightness.Level != 100.0
        GammaBrightness.Apply()
        GammaBrightness._Show()
    }

    static Toggle() {
        if (GammaBrightness.Active) {
            GammaBrightness.Saved := GammaBrightness.Level
            GammaBrightness.Level := 100.0
            GammaBrightness.Active := false
        } else {
            GammaBrightness.Level := GammaBrightness.Saved = 100.0 ? GammaBrightness.DefaultSaved : GammaBrightness.Saved
            GammaBrightness.Active := true
        }
        GammaBrightness.Apply()
        GammaBrightness._Show()
    }

    static Apply() => GammaBrightness.SetGamma(GammaBrightness.GammaFor(GammaBrightness.Level))

    static Reset() => GammaBrightness.SetGamma(1.0)

    ; Applies a gamma ramp (output = (input/255)^gamma) to every attached display.
    static SetGamma(gamma) {
        ramp := Buffer(256 * 2 * 3)
        loop 256 {
            value := Min(65535, Round(((A_Index - 1) / 255) ** gamma * 65535))
            NumPut("UShort", value, ramp, (A_Index - 1) * 2)
            NumPut("UShort", value, ramp, 512 + (A_Index - 1) * 2)
            NumPut("UShort", value, ramp, 1024 + (A_Index - 1) * 2)
        }
        displayIndex := 0
        loop {
            device := Buffer(840)
            NumPut("UInt", 840, device, 0)
            if (!DllCall("EnumDisplayDevices", "Ptr", 0, "UInt", displayIndex, "Ptr", device, "UInt", 0))
                break
            deviceName := StrGet(device.Ptr + 4, 32, "UTF-16")
            ; DISPLAY_DEVICE_ATTACHED_TO_DESKTOP
            if (NumGet(device, 324, "UInt") & 0x1) {
                hdc := DllCall("CreateDC", "Str", deviceName, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr")
                if (hdc) {
                    DllCall("SetDeviceGammaRamp", "Ptr", hdc, "Ptr", ramp.Ptr)
                    DllCall("DeleteDC", "Ptr", hdc)
                }
            }
            displayIndex++
        }
    }

    static _Show() => Toast.ShowToast({ fadeDelay: 800 }, "Brightness:", GammaBrightness.Level "%")
}


; ---------------- Windows Night Light            ------------------------------

; Night Light state lives in CloudStore binary blobs under HKCU.
; mutate: on
class NightLight {
    static StatePath := "Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default$windows.data.bluelightreduction.bluelightreductionstate\windows.data.bluelightreduction.bluelightreductionstate"
    static SettingsPath := "Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default$windows.data.bluelightreduction.settings\windows.data.bluelightreduction.settings"
    static MinKelvin := 1200.0
    static MaxKelvin := 6500.0

    ; Pure: strength percent (0 = off, 100 = warmest) <-> kelvin <-> blob bytes.
    static KelvinFor(percent) {
        p := Max(0, Min(100, Round(percent)))
        return NightLight.MaxKelvin - (p / 100.0) * (NightLight.MaxKelvin - NightLight.MinKelvin)
    }

    static PercentFor(kelvin) {
        return Round(100.0 - ((kelvin - NightLight.MinKelvin) / (NightLight.MaxKelvin - NightLight.MinKelvin)) * 100.0)
    }

    static EncodeKelvin(kelvin) {
        hi := Floor(kelvin / 64.0)
        lo := ((kelvin - (hi * 64.0)) * 2.0) + 128.0
        return { lo: Round(lo), hi: Round(hi) }
    }

    static DecodeKelvin(lo, hi) => (hi * 64) + ((lo - 128) / 2)

    ; Pure: next strength for a step of `delta` (snaps to multiples of |delta|).
    static NextStrength(current, delta) {
        step := Abs(delta)
        if (delta > 0) {
            next := Ceil(current / step) * step
            if (next <= current)
                next := current + step
            return Min(100, next)
        }
        next := Floor(current / step) * step
        if (next >= current)
            next := current - step
        return Max(0, next)
    }

    ; mutate: off (Win32/WMI/registry I/O)
    static Toggle() {
        try {
            data := NightLight._Read(NightLight.StatePath)
            if !data
                throw Error("Night Light state not found")
            size := data.Size
            disabling := NumGet(data, 18, "UChar") = 0x15
            newSize := disabling ? 41 : 43
            out := Buffer(newSize, 0)
            DllCall("RtlMoveMemory", "Ptr", out.Ptr, "Ptr", data.Ptr, "UPtr", 22)
            if (disabling) {
                if (size > 25)
                    DllCall("RtlMoveMemory", "Ptr", out.Ptr + 23, "Ptr", data.Ptr + 25, "UPtr", Min(size - 25, newSize - 23))
            } else {
                if (size > 23)
                    DllCall("RtlMoveMemory", "Ptr", out.Ptr + 25, "Ptr", data.Ptr + 23, "UPtr", Min(size - 23, newSize - 25))
                NumPut("UChar", 0x10, out, 23)
                NumPut("UChar", 0x00, out, 24)
            }
            NumPut("UChar", disabling ? 0x13 : 0x15, out, 18)
            NightLight._BumpTimestamp(out)
            NightLight._Write(NightLight.StatePath, out)
            Toast.ShowToast({ fadeDelay: 800 }, "Night Light:", disabling ? "OFF" : "ON")
        } catch as err {
            Toast.ShowToast({ fadeDelay: 2000, color: "Red" }, "Night Light error", err.Message)
        }
    }

    static GetStrength() {
        data := NightLight._Read(NightLight.SettingsPath)
        if !data
            return 0
        offset := data.Size > 0x26 ? 0x25 : 0x23
        return NightLight.PercentFor(NightLight.DecodeKelvin(NumGet(data, offset, "UChar"), NumGet(data, offset + 1, "UChar")))
    }

    static SetStrength(percent) {
        data := NightLight._Read(NightLight.SettingsPath)
        if !data
            return false
        enc := NightLight.EncodeKelvin(NightLight.KelvinFor(percent))
        offset := data.Size > 0x26 ? 0x25 : 0x23
        NumPut("UChar", enc.lo, data, offset)
        NumPut("UChar", enc.hi, data, offset + 1)
        NightLight._BumpTimestamp(data)
        return NightLight._Write(NightLight.SettingsPath, data)
    }

    static Adjust(delta) {
        try {
            next := NightLight.NextStrength(NightLight.GetStrength(), delta)
            if !NightLight.SetStrength(next)
                throw Error("write failed")
            Toast.ShowToast({ fadeDelay: 800 }, "Night Light Strength:", next "%")
        } catch as err {
            Toast.ShowToast({ fadeDelay: 2000, color: "Red" }, "Night Light strength error", err.Message)
        }
    }

    static Set(percent) {
        if NightLight.SetStrength(percent)
            Toast.ShowToast({ fadeDelay: 800 }, "Night Light Strength:", Round(percent) "%")
        else
            Toast.ShowToast({ fadeDelay: 2000, color: "Red" }, "Night Light strength error")
    }

    ; Increments the first non-0xFF byte of the change counter (bytes 10..14).
    static _BumpTimestamp(buf) {
        loop 5 {
            idx := 9 + A_Index
            val := NumGet(buf, idx, "UChar")
            if (val != 0xFF) {
                NumPut("UChar", val + 1, buf, idx)
                return
            }
        }
    }

    static _Read(path) {
        handle := 0
        if (DllCall("advapi32\RegOpenKeyExW", "UPtr", 0x80000001, "Str", path, "UInt", 0, "UInt", 0x20019, "UPtr*", &handle) != 0)
            return ""
        try {
            size := 0
            DllCall("advapi32\RegQueryValueExW", "UPtr", handle, "Str", "Data", "UInt", 0, "UInt", 0, "UPtr", 0, "UInt*", &size)
            if (size = 0)
                return ""
            data := Buffer(size)
            if (DllCall("advapi32\RegQueryValueExW", "UPtr", handle, "Str", "Data", "UInt", 0, "UInt", 0, "Ptr", data.Ptr, "UInt*", &size) != 0)
                return ""
            return data
        } finally {
            DllCall("advapi32\RegCloseKey", "UPtr", handle)
        }
    }

    static _Write(path, data) {
        handle := 0
        if (DllCall("advapi32\RegOpenKeyExW", "UPtr", 0x80000001, "Str", path, "UInt", 0, "UInt", 0x2003F, "UPtr*", &handle) != 0)
            return false
        try {
            ; REG_BINARY = 3
            return DllCall("advapi32\RegSetValueExW", "UPtr", handle, "Str", "Data", "UInt", 0, "UInt", 3, "Ptr", data.Ptr, "UInt", data.Size) = 0
        } finally {
            DllCall("advapi32\RegCloseKey", "UPtr", handle)
        }
    }
}
