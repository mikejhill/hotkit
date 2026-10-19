#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#NoTrayIcon

; Unit test entry point. Usage: AutoHotkey64.exe /ErrorStdOut tests\unit\RunUnit.ahk [--filter=Name]
; Every *.Test.ahk in this folder must be included below (enforced by tools/lint.py).

#Include %A_ScriptDir%\..\lib\TestRunner.ahk
#Include %A_ScriptDir%\..\..\src\Lib\Debugger.ahk
#Include %A_ScriptDir%\..\..\src\Lib\Toast.ahk
#Include %A_ScriptDir%\..\..\src\Lib\JSON.ahk
#Include %A_ScriptDir%\..\..\src\Lib\HotkeyText.ahk
#Include %A_ScriptDir%\..\..\src\Lib\AppUtil.ahk
#Include %A_ScriptDir%\..\..\src\Core\Paths.ahk
#Include %A_ScriptDir%\..\..\src\Core\Config.ahk
#Include %A_ScriptDir%\..\..\src\Core\ActionRegistry.ahk
#Include %A_ScriptDir%\..\..\src\Core\Bindings.ahk
#Include %A_ScriptDir%\..\..\src\Core\Plugins.ahk
#Include %A_ScriptDir%\..\..\src\Ui\ShortcutOsd.ahk
#Include %A_ScriptDir%\..\..\src\Modules\Apps.ahk
#Include %A_ScriptDir%\..\..\src\Modules\QuickWindows.ahk
#Include %A_ScriptDir%\..\..\src\Modules\Windows.ahk
#Include %A_ScriptDir%\..\..\src\Modules\Desktop.ahk
#Include %A_ScriptDir%\..\..\src\Modules\Display.ahk
#Include %A_ScriptDir%\..\..\examples\plugins\BreakReminder\BreakSchedule.ahk
#Include %A_ScriptDir%\..\..\examples\plugins\QuickNote\NoteFormat.ahk
#Include %A_ScriptDir%\..\..\examples\plugins\Stopwatch\StopwatchClock.ahk

#Include %A_ScriptDir%\ActionRegistry.Test.ahk
#Include %A_ScriptDir%\Bindings.Test.ahk
#Include %A_ScriptDir%\Config.Test.ahk
#Include %A_ScriptDir%\DisplayMath.Test.ahk
#Include %A_ScriptDir%\ExamplePlugins.Test.ahk
#Include %A_ScriptDir%\HotkeyText.Test.ahk
#Include %A_ScriptDir%\JSON.Test.ahk
#Include %A_ScriptDir%\Modules.Test.ahk
#Include %A_ScriptDir%\Paths.Test.ahk
#Include %A_ScriptDir%\Plugins.Test.ahk
#Include %A_ScriptDir%\WindowMatcher.Test.ahk

TestRunner.Run()
