#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\Toast.ahk

class WmiBrightnessController {
    monitors := []
    static s_instance := 0

    static Initialize() {
        if (this.s_instance != 0) {
            return this.s_instance
        }

        instance := WmiBrightnessController()
        instance.RefreshMonitors()
        this.s_instance := instance
        return instance
    }

    static NormalizeInstanceKey(instanceName) {
        if (RegExMatch(instanceName, "^[^\\]+\\([^\\]+)", &match)) {
            return StrUpper(match[1])
        }
        return ""
    }

    RefreshMonitors() {
        this.monitors := []

        try {
            wmi := ComObjGet("winmgmts:\\.\root\WMI")
        } catch as err {
            return 0
        }

        methodsByInstance := Map()
        for item in wmi.ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods") {
            instanceKey := StrUpper(item.InstanceName)
            methodsByInstance[instanceKey] := item
        }

        for item in wmi.ExecQuery("SELECT * FROM WmiMonitorBrightness") {
            instanceName := item.InstanceName
            lookupKey := StrUpper(instanceName)
            methods := methodsByInstance.Has(lookupKey) ? methodsByInstance[lookupKey] : 0
            idKey := WmiBrightnessController.NormalizeInstanceKey(instanceName)
            this.monitors.Push({
                instanceName: instanceName,
                idKey: idKey,
                brightness: item,
                methods: methods
            })
        }

        return this.monitors.Length
    }

    GetIdKeys() {
        keys := Map()
        for monitor in this.monitors {
            if (monitor.idKey != "") {
                keys[monitor.idKey] := true
            }
        }
        return keys
    }

    GetPrimaryBrightness() {
        if (this.monitors.Length = 0) {
            return -1
        }

        try {
            return this.monitors[1].brightness.CurrentBrightness
        } catch as err {
            return -1
        }
    }

    AdjustBrightness(delta, timeout := 1, showToast := true) {
        if (this.monitors.Length = 0) {
            if (showToast) {
                Toast.ShowToast({ fadeDelay: 1000 }, { text: "!", size: 24 }, { text: "No WMI displays", size: 14 })
            }
            return { success: 0, value: -1 }
        }

        current := this.GetPrimaryBrightness()
        if (current < 0) {
            if (showToast) {
                Toast.ShowToast({ fadeDelay: 1000 }, { text: "!", size: 24 }, { text: "Brightness read failed", size: 14 })
            }
            return { success: 0, value: -1 }
        }

        newValue := Max(0, Min(100, current + delta))
        result := this.SetAllMonitors(newValue, timeout, showToast)
        return { success: result.success, value: newValue }
    }

    SetAllMonitors(value, timeout := 1, showToast := true) {
        if (this.monitors.Length = 0) {
            if (showToast) {
                Toast.ShowToast({ fadeDelay: 1000 }, { text: "!", size: 24 }, { text: "No WMI displays", size: 14 })
            }
            return { success: 0, value: -1 }
        }

        newValue := Max(0, Min(100, Integer(value)))
        successCount := 0

        for monitor in this.monitors {
            if (!monitor.methods) {
                continue
            }

            try {
                monitor.methods.WmiSetBrightness(timeout, newValue)
                successCount += 1
            } catch as err {
                ; Skip failures
            }
        }

        if (showToast) {
            if (successCount > 0) {
                Toast.ShowToast({ fadeDelay: 800 }, { text: "OK", size: 24 }, { text: "Brightness " . newValue, size: 14 })
            } else {
                Toast.ShowToast({ fadeDelay: 1000 }, { text: "!", size: 24 }, { text: "Brightness set failed", size: 14 })
            }
        }

        return { success: successCount, value: newValue }
    }
}
