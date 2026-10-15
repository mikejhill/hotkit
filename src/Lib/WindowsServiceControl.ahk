#Requires AutoHotkey v2.0

; SCM adapter. Requests only the permission needed by each operation.
class WindowsServiceControl {
    static WithService(name, access, action) {
        manager := DllCall("Advapi32\OpenSCManagerW", "Ptr", 0, "Ptr", 0, "UInt", 1, "Ptr")
        if !manager
            throw OSError(A_LastError, "OpenSCManager")
        service := 0
        try {
            service := DllCall("Advapi32\OpenServiceW", "Ptr", manager, "Str", name, "UInt", access, "Ptr")
            if !service
                throw OSError(A_LastError, "OpenService: " name)
            return action(service)
        } finally {
            if service
                DllCall("Advapi32\CloseServiceHandle", "Ptr", service)
            DllCall("Advapi32\CloseServiceHandle", "Ptr", manager)
        }
    }

    static Status(name) => this.WithService(name, 0x4, (handle) => this.ReadStatus(handle))

    static ReadStatus(service) {
        status := Buffer(36, 0)
        needed := 0
        if !DllCall("Advapi32\QueryServiceStatusEx", "Ptr", service, "Int", 0,
            "Ptr", status, "UInt", status.Size, "UInt*", &needed)
            throw OSError(A_LastError, "QueryServiceStatusEx")
        return NumGet(status, 4, "UInt")
    }

    static Start(name) {
        if this.Status(name) != 1
            return
        this.WithService(name, 0x10, (handle) => this.StartHandle(handle))
    }

    static StartHandle(service) {
        if !DllCall("Advapi32\StartServiceW", "Ptr", service, "UInt", 0, "Ptr", 0) {
            errorCode := A_LastError
            if errorCode != 1056
                throw OSError(errorCode, "StartService")
        }
    }

    static Stop(name) {
        if this.Status(name) != 4
            return
        this.WithService(name, 0x20, (handle) => this.StopHandle(handle))
    }

    static StopHandle(service) {
        status := Buffer(28, 0)
        if !DllCall("Advapi32\ControlService", "Ptr", service, "UInt", 1, "Ptr", status) {
            errorCode := A_LastError
            if errorCode != 1062
                throw OSError(errorCode, "ControlService")
        }
    }
}
