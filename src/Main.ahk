#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, OutputDebug

; hotkit entry point. Run this one script; everything personal
; (key bindings, apps, plugins) comes from %USERPROFILE%\.config\hotkit.
; See README.md and docs/ for details.

; Non-interactive modes (and CI, via HOTKIT_HEADLESS=1) must never block
; on an error dialog.
if (EnvGet("HOTKIT_HEADLESS") = "1")
    OnError(HeadlessErrorHandler)
for arg in A_Args {
    if (arg = "--check" || arg = "--list-actions" || arg = "--sync-plugins") {
        OnError(HeadlessErrorHandler)
        break
    }
}

; Libraries in src\Lib are also available to plugins as #Include <Name>.
#Include %A_ScriptDir%\Lib\Debugger.ahk
#Include %A_ScriptDir%\Lib\Toast.ahk
#Include %A_ScriptDir%\Lib\JSON.ahk
#Include %A_ScriptDir%\Lib\PackageVirtualization.ahk

#Include %A_ScriptDir%\Core\Paths.ahk
#Include %A_ScriptDir%\Core\StatusLog.ahk
#Include %A_ScriptDir%\Core\Config.ahk
#Include %A_ScriptDir%\Lib\HotkeyText.ahk
#Include %A_ScriptDir%\Core\ActionRegistry.ahk
#Include %A_ScriptDir%\Core\Bindings.ahk
#Include %A_ScriptDir%\Core\Plugins.ahk
#Include %A_ScriptDir%\Core\Tray.ahk
#Include %A_ScriptDir%\Core\App.ahk
#Include %A_ScriptDir%\Ui\ShortcutOsd.ahk

#Include %A_ScriptDir%\Modules\Apps.ahk
#Include %A_ScriptDir%\Modules\QuickWindows.ahk
#Include %A_ScriptDir%\Modules\Windows.ahk
#Include %A_ScriptDir%\Modules\Desktop.ahk
#Include %A_ScriptDir%\Modules\Display.ahk

; User plugins (generated, git-ignored). Missing on first run; App.Main creates
; it and reloads.
#Include *i %A_ScriptDir%\..\local\plugins.generated.ahk

App.Main(A_Args)
