#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\Toast.ahk
#Include %A_LineFile%\..\Debugger.ahk

; ==============================================================================
; DDC/CI Monitor Controller - Private callback
; ==============================================================================

DDCCI_NormalizeMonitorKey(identifier) {
    if (RegExMatch(identifier, "^[^\\]+\\([^\\]+)", &match)) {
        return StrUpper(match[1])
    }
    return ""
}

DDCCI_GetMonitorDeviceInfo(hMonitor) {
    info := { deviceName: "", deviceId: "", idKey: "" }

    miSize := 104
    monitorInfo := Buffer(miSize, 0)
    NumPut("UInt", miSize, monitorInfo, 0)

    if (!DllCall("user32\GetMonitorInfoW", "Ptr", hMonitor, "Ptr", monitorInfo)) {
        return info
    }

    deviceName := StrGet(monitorInfo.Ptr + 40, 32, "UTF-16")
    info.deviceName := deviceName

    displayDevice := Buffer(840, 0)
    NumPut("UInt", 840, displayDevice, 0)
    if (DllCall("user32\EnumDisplayDevicesW", "Str", deviceName, "UInt", 0, "Ptr", displayDevice, "UInt", 0)) {
        deviceId := StrGet(displayDevice.Ptr + 328, 128, "UTF-16")
        info.deviceId := deviceId
        info.idKey := DDCCI_NormalizeMonitorKey(deviceId)
    }

    return info
}

DDCCI_EnumDisplayMonitorsProc(hMonitor, hdcMonitor, lprcMonitor, dwData) {
    instance := DDCCIController.s_enumeratingInstance

    if (instance = 0) {
        return true
    }

    ; Get physical monitor count for this display
    physicalCount := 0
    result := DllCall("dxva2\GetNumberOfPhysicalMonitorsFromHMONITOR"
        , "ptr", hMonitor
        , "uint*", &physicalCount
        , "int")

    if (!result || physicalCount = 0) {
        return true ; Continue enumeration
    }

    ; Allocate buffer for physical monitor handles
    ; PHYSICAL_MONITOR structure is: HANDLE (ptr) + 128 WCHARs
    bufferSize := physicalCount * (A_PtrSize + 256)
    physicalMonitors := Buffer(bufferSize, 0)

    ; Get physical monitor handles
    result := DllCall("dxva2\GetPhysicalMonitorsFromHMONITOR"
        , "ptr", hMonitor
        , "uint", physicalCount
        , "ptr", physicalMonitors
        , "int")

    if (result) {
        deviceInfo := DDCCI_GetMonitorDeviceInfo(hMonitor)

        ; Extract each physical monitor handle
        loop physicalCount {
            offset := (A_Index - 1) * (A_PtrSize + 256)
            hPhysical := NumGet(physicalMonitors, offset, "ptr")
            instance.monitorHandles.Push(hPhysical)
            instance.monitorEntries.Push({
                hPhysical: hPhysical,
                hMonitor: hMonitor,
                deviceName: deviceInfo.deviceName,
                deviceId: deviceInfo.deviceId,
                idKey: deviceInfo.idKey
            })
        }
    }

    return true ; Continue enumeration
}

/**
 * DDC/CI Monitor Controller
 *
 * Direct hardware control of external monitors via DDC/CI protocol.
 * Supports brightness, contrast, and other VCP (Virtual Control Panel) codes.
 * No external tools required - uses Windows API (dxva2.dll).
 *
 * VCP Codes Reference:
 *   0x10: Brightness
 *   0x12: Contrast
 *   0x60: Input Source
 *   0xD6: Power Mode
 *
 * Usage (Singleton):
 *   DDCCIController.Initialize()
 *   DDCCIController.AdjustAllMonitors(0x10, 10)  ; Increase brightness by 10
 */
class DDCCIController {
    monitorHandles := []
    monitorEntries := []
    isInitialized := false
    displayChangeHandler := 0
    static s_enumeratingInstance := 0  ; Temporary storage for callback access during Initialize()
    static s_instance := 0              ; Singleton instance

    /**
     * Initialize DDC/CI by enumerating all physical monitors
     * Creates singleton on first call, returns existing instance on subsequent calls
     * Automatically monitors for display changes and refreshes monitor list when needed
     */
    static Initialize() {
        if (this.s_instance != 0) {
            return this.s_instance  ; Return existing singleton
        }

        instance := DDCCIController()
        instance.monitorHandles := []
        instance.monitorEntries := []

        ; Register cleanup for this instance (only once)
        if (!instance.isInitialized) {
            OnExit((*) => instance.Cleanup())
            instance.isInitialized := true

            ; Register for WM_DISPLAYCHANGE messages to auto-refresh on monitor connect/disconnect
            instance._RegisterDisplayChangeHandler()
        }

        ; Store instance reference for callback access (using static class variable)
        DDCCIController.s_enumeratingInstance := instance

        ; Create callback and enumerate displays
        callback := CallbackCreate(DDCCI_EnumDisplayMonitorsProc)

        ; Enumerate all display monitors
        DllCall("user32\EnumDisplayMonitors"
            , "ptr", 0              ; hdc (NULL = all displays)
            , "ptr", 0              ; lprcClip (NULL = entire virtual screen)
            , "ptr", callback
            , "ptr", 0              ; dwData (not needed)
            , "int")

        CallbackFree(callback)

        ; Clear static reference
        DDCCIController.s_enumeratingInstance := 0

        ; Store singleton
        this.s_instance := instance
        return instance
    }

    /**
     * Get VCP feature value from a monitor
     * @param hMonitor Physical monitor handle
     * @param vcpCode VCP code (e.g., 0x10 for brightness)
     * @returns Object with {current, max} or {current: -1, max: -1} on error
     */
    GetVCPFeature(hMonitor, vcpCode) {
        current := 0
        maximum := 0

        result := DllCall("dxva2\GetVCPFeatureAndVCPFeatureReply"
            , "ptr", hMonitor
            , "uchar", vcpCode
            , "uint*", 0           ; pvct (feature type)
            , "uint*", &current
            , "uint*", &maximum
            , "int")

        return (result) ? { current: current, max: maximum } : { current: -1, max: -1 }
    }

    /**
     * Set VCP feature value on a monitor
     * @param hMonitor Physical monitor handle
     * @param vcpCode VCP code (e.g., 0x10 for brightness)
     * @param value New value to set
     * @returns true on success, false on failure
     */
    SetVCPFeature(hMonitor, vcpCode, value) {
        return DllCall("dxva2\SetVCPFeature"
            , "ptr", hMonitor
            , "uchar", vcpCode
            , "uint", value
            , "int")
    }

    /**
     * Adjust a VCP feature on all monitors by a delta
     * All monitors are synchronized to the same value based on the primary monitor
     * @param vcpCode VCP code to adjust
     * @param delta Amount to adjust (+/-)
     * @param showToast Whether to show toast notification (default: true)
     */
    AdjustAllMonitors(vcpCode, delta, showToast := true) {
        return this.AdjustMonitors(vcpCode, delta, this.monitorEntries, showToast)
    }

    /**
     * Set a VCP feature to a specific value on all monitors (optimized parallel execution)
     * @param vcpCode VCP code to set
     * @param value Value to set
     * @param showToast Whether to show toast notification (default: true)
     * @returns Number of monitors successfully updated
     */
    SetAllMonitors(vcpCode, value, showToast := true) {
        return this.SetMonitors(vcpCode, value, this.monitorEntries, showToast)
    }

    AdjustMonitors(vcpCode, delta, monitorEntries, showToast := true) {
        if (monitorEntries.Length = 0) {
            if (showToast) {
                Toast.ShowToast({ fadeDelay: 1000 }, { text: "⚠", size: 24 }, { text: "No monitors found", size: 14 })
            }
            return { success: 0, value: -1 }
        }

        featureName := this.GetVCPCodeName(vcpCode)

        ; Use first monitor as primary/authority
        hPrimary := monitorEntries[1].hPhysical
        feature := this.GetVCPFeature(hPrimary, vcpCode)

        if (feature.current = -1) {
            if (showToast) {
                Toast.ShowToast({ fadeDelay: 1000 }, { text: "⚠", size: 24 }, { text: featureName . " read failed",
                    size: 14 })
            }
            return { success: 0, value: -1 }
        }

        ; Calculate new value (clamp to valid range)
        newValue := feature.current + delta
        if (newValue < 0) {
            newValue := 0
        }
        if (newValue > feature.max) {
            newValue := feature.max
        }

        ; Set same value on all monitors in parallel
        tasks := []
        for index, entry in monitorEntries {
            tasks.Push(this._SetVCPAsync(entry.hPhysical, vcpCode, newValue))
        }

        successCount := 0
        for index, task in tasks {
            if (task) {
                successCount++
            }
        }

        if (showToast) {
            if (successCount > 0) {
                ; Show toast with new value
                icon := (delta > 0) ? "🔆" : "🔅"
                Toast.ShowToast({ fadeDelay: 800 }, { text: icon, size: 24 }, { text: featureName . " " . newValue,
                    size: 14 })
            } else {
                Toast.ShowToast({ fadeDelay: 1000 }, { text: "⚠", size: 24 }, { text: featureName . " adjust failed",
                    size: 14 })
            }
        }

        return { success: successCount, value: newValue }
    }

    SetMonitors(vcpCode, value, monitorEntries, showToast := true) {
        if (monitorEntries.Length = 0) {
            if (showToast) {
                Toast.ShowToast({ fadeDelay: 1000 }, { text: "⚠", size: 24 }, { text: "No monitors found", size: 14 })
            }
            return { success: 0, value: -1 }
        }

        ; Launch parallel tasks for each monitor
        tasks := []
        for index, entry in monitorEntries {
            tasks.Push(this._SetVCPAsync(entry.hPhysical, vcpCode, value))
        }

        ; Wait for all tasks to complete
        successCount := 0
        for index, task in tasks {
            if (task) {
                successCount++
            }
        }

        if (showToast) {
            featureName := this.GetVCPCodeName(vcpCode)
            if (successCount > 0) {
                Toast.ShowToast({ fadeDelay: 800 }, { text: "✓", size: 24 }, { text: featureName . " " . value, size: 14 })
            } else {
                Toast.ShowToast({ fadeDelay: 1000 }, { text: "⚠", size: 24 }, { text: featureName . " set failed", size: 14 })
            }
        }

        return { success: successCount, value: value }
    }

    /**
     * Helper method to set VCP feature (used for parallel execution)
     */
    _SetVCPAsync(hMonitor, vcpCode, value) {
        return this.SetVCPFeature(hMonitor, vcpCode, value)
    }

    /**
     * Swap brightness between saved and default value
     * @param defaultValue Default brightness value (e.g., 100)
     * @param savedValueRef Reference to variable holding saved brightness
     * @param showToast Whether to show toast notification (default: true)
     */
    SwapBrightness(defaultValue, &savedValueRef, showToast := true) {
        if (this.monitorHandles.Length = 0) {
            if (showToast) {
                Toast.ShowToast({ fadeDelay: 1000 }, { text: "⚠", size: 24 }, { text: "No monitors found", size: 14 })
            }
            return
        }

        ; Get current brightness from first monitor
        hPrimary := this.monitorHandles[1]
        feature := this.GetVCPFeature(hPrimary, 0x10)

        if (feature.current = -1) {
            if (showToast) {
                Toast.ShowToast({ fadeDelay: 1000 }, { text: "⚠", size: 24 }, { text: "Brightness read failed", size: 14 })
            }
            return
        }

        ; Determine new value
        newValue := 0
        if (feature.current = defaultValue) {
            ; Switch to saved value (or 85% if not set)
            newValue := (savedValueRef = defaultValue) ? 85 : savedValueRef
        } else {
            ; Save current and switch to default
            savedValueRef := feature.current
            newValue := defaultValue
        }

        ; Apply to all monitors
        this.SetAllMonitors(0x10, newValue, showToast)
    }

    /**
     * Get friendly name for VCP code
     * @param vcpCode VCP code
     * @returns String name of the feature
     */
    GetVCPCodeName(vcpCode) {
        switch vcpCode {
            case 0x10: return "Brightness"
            case 0x12: return "Contrast"
            case 0x60: return "Input Source"
            case 0xD6: return "Power Mode"
            default: return "VCP 0x" . Format("{:X}", vcpCode)
        }
    }

    /**
     * Cleanup: Release all physical monitor handles
     */
    Cleanup() {
        if (this.monitorHandles.Length = 0) {
            return  ; Already cleaned up
        }

        for index, hMonitor in this.monitorHandles {
            DllCall("dxva2\DestroyPhysicalMonitor", "ptr", hMonitor, "int")
        }

        this.monitorHandles := []
        this.monitorEntries := []
    }

    /**
     * Refresh monitor list by re-enumerating all physical monitors
     * Automatically called when WM_DISPLAYCHANGE message is received
     * Can also be called manually if needed
     * @returns Number of monitors found
     */
    RefreshMonitors() {
        ; Cleanup existing handles
        this.Cleanup()

        this.monitorHandles := []
        this.monitorEntries := []
        DDCCIController.s_enumeratingInstance := this

        ; Create callback and enumerate displays
        callback := CallbackCreate(DDCCI_EnumDisplayMonitorsProc)

        ; Enumerate all display monitors
        DllCall("user32\EnumDisplayMonitors"
            , "ptr", 0              ; hdc (NULL = all displays)
            , "ptr", 0              ; lprcClip (NULL = entire virtual screen)
            , "ptr", callback
            , "ptr", 0              ; dwData (not needed)
            , "int")

        CallbackFree(callback)

        ; Clear static reference
        DDCCIController.s_enumeratingInstance := 0

        return this.monitorHandles.Length
    }

    /**
     * Register for WM_DISPLAYCHANGE messages to auto-refresh monitor list
     * When a monitor is connected/disconnected, the list is automatically refreshed
     */
    _RegisterDisplayChangeHandler() {
        instance := this

        ; Create a closure that captures the instance
        handler(wParam, lParam, msg, hwnd) {
            ; WM_DISPLAYCHANGE is sent when display settings change
            ; wParam contains new bits per pixel
            ; lParam contains width/height of display change

            ; Only refresh if we have monitors already initialized
            if (instance.monitorEntries.Length > 0) {
                previousCount := instance.monitorEntries.Length
                newCount := instance.RefreshMonitors()

                ; Log if monitor count changed
                if (previousCount != newCount) {
                    Debugger.Log("Display change detected. Monitors: " . previousCount . " -> " . newCount, "INFO")
                }
            }
            return 0
        }

        this.displayChangeHandler := handler

        ; WM_DISPLAYCHANGE = 0x007E
        OnMessage(0x007E, this.displayChangeHandler)
    }

    /**
     * Destructor: Automatically cleanup on object destruction
     */
    __Delete() {
        this.Cleanup()
    }

    ; ==================== Static Convenience Methods      ==============================

    /**
     * Static method: Manually refresh the monitor list
     * Automatically initializes singleton if needed
     * @returns Number of monitors found
     */
    static RefreshMonitorList() {
        instance := this.Initialize()
        count := instance.RefreshMonitors()
        Toast.ShowToast({ fadeDelay: 1000 }, { text: "✓", size: 24 }, { text: "Monitors: " . count, size: 14 })
        return count
    }

    /**
     * Static method: Adjust brightness on all monitors
     * Automatically initializes singleton on first call
     */
    static AdjustBrightness(delta, showToast := true) {
        instance := this.Initialize()
        instance.AdjustAllMonitors(0x10, delta, showToast)
    }

    /**
     * Static method: Set brightness on all monitors to specific value
     * Automatically initializes singleton on first call
     */
    static SetBrightness(value, showToast := true) {
        instance := this.Initialize()
        instance.SetAllMonitors(0x10, value, showToast)
    }
}
