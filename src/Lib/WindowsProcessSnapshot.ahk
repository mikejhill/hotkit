#Requires AutoHotkey v2.0

; Native process enumeration; no WMI polling or subprocess launches.
class WindowsProcessSnapshot {
    static List() {
        snapshot := DllCall("Kernel32\CreateToolhelp32Snapshot", "UInt", 2, "UInt", 0, "Ptr")
        if snapshot = -1
            throw OSError(A_LastError, "CreateToolhelp32Snapshot")
        size := A_PtrSize = 8 ? 568 : 556
        nameOffset := A_PtrSize = 8 ? 44 : 36
        entry := Buffer(size, 0)
        NumPut("UInt", size, entry)
        result := []
        try {
            more := DllCall("Kernel32\Process32FirstW", "Ptr", snapshot, "Ptr", entry)
            while more {
                result.Push({Pid: NumGet(entry, 8, "UInt"), Name: StrGet(entry.Ptr + nameOffset, 260, "UTF-16")})
                more := DllCall("Kernel32\Process32NextW", "Ptr", snapshot, "Ptr", entry)
            }
            if A_LastError != 18
                throw OSError(A_LastError, "Process32 enumeration")
        } finally DllCall("Kernel32\CloseHandle", "Ptr", snapshot)
        return result
    }

    static Path(pid) {
        process := DllCall("Kernel32\OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
        if !process
            return ""
        try {
            length := 32768
            path := Buffer(length * 2, 0)
            if DllCall("Kernel32\QueryFullProcessImageNameW", "Ptr", process, "UInt", 0, "Ptr", path, "UInt*", &length)
                return StrGet(path, length, "UTF-16")
            return ""
        } finally DllCall("Kernel32\CloseHandle", "Ptr", process)
    }
}
