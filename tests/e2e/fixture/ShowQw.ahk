#Requires AutoHotkey v2.0
#NoTrayIcon

; Launch command for the "qw" quick window: like a tray app started a second
; time, it shows its existing (hidden) window instead of opening a new one.
DetectHiddenWindows(true)
if WinExist("hotkit-e2e-qw")
    WinShow()
