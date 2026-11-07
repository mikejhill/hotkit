#Requires AutoHotkey v2.0

; Detects whether this process inherited an MSIX app package's virtualized
; view of the user profile. That happens when hotkit is launched from a
; packaged app's child process (for example a terminal inside a packaged
; desktop app): writes to HKCU and %APPDATA% land in the package's private
; copy, so Windows and other apps never see them, while this process reads
; its own writes back as if they had worked.
class PackageVirtualization {
    ; mutate: off
    ; Returns the name of the package folder that a probe write to %APPDATA%
    ; was redirected into, or "" when writes reach the real profile.
    static RedirectingPackage() {
        name := "hotkit-virtualization-probe-" ProcessExist()
        probe := A_AppData "\" name
        try FileAppend("", probe)
        catch
            return ""
        found := ""
        loop files EnvGet("LOCALAPPDATA") "\Packages\*", "D" {
            if FileExist(A_LoopFileFullPath "\LocalCache\Roaming\" name) {
                found := A_LoopFileName
                break
            }
        }
        try FileDelete(probe)
        return found
    }
    ; mutate: on
}
