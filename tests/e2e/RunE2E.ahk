#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#NoTrayIcon

; End-to-end tests: launches src\Main.ahk as a separate process with a fixture
; config + probe plugin, drives it with synthetic keystrokes, and asserts on the
; probe file and on the shortcut overlay window. Steps run in name order.
;
; Usage: AutoHotkey64.exe /ErrorStdOut tests\e2e\RunE2E.ahk

#Include %A_ScriptDir%\..\lib\TestRunner.ahk

class E2E_Tests {
    static Dir := ""
    static Probe := ""
    static Pid := 0
    static Main := A_ScriptDir "\..\..\src\Main.ahk"

    static WriteConfig(extra := "") {
        text := FileRead(A_ScriptDir "\fixture\config.template.json", "UTF-8")
        text := StrReplace(text, "{{PROBE}}", StrReplace(E2E_Tests.Probe, "\", "\\"))
        text := StrReplace(text, "{{EXTRA}}", extra)
        f := FileOpen(E2E_Tests.Dir "\config.json", "w", "UTF-8-RAW")
        f.Write(text)
        f.Close()
    }

    static Marks() => FileExist(E2E_Tests.Probe) ? StrSplit(Trim(FileRead(E2E_Tests.Probe), "`n"), "`n") : []

    static Count(name) {
        n := 0
        for m in E2E_Tests.Marks()
            n += (m = name)
        return n
    }

    ; PID of the running app (it reloads itself, so the launch PID goes stale).
    static AppPid() {
        pid := 0
        for m in E2E_Tests.Marks() {
            if (SubStr(m, 1, 4) = "pid:")
                pid := Integer(SubStr(m, 5))
        }
        return pid
    }

    static WaitFor(name, count := 1, timeoutMs := 20000) {
        start := A_TickCount
        while (A_TickCount - start < timeoutMs) {
            if (E2E_Tests.Count(name) >= count)
                return true
            Sleep(100)
        }
        Assert.Fail("timed out waiting for mark '" name "' x" count "; marks: " Assert.Show(E2E_Tests.Marks()))
    }

    static Press(hk) {
        SendLevel(1)
        SendEvent(HotkeyText.ToSendEvent(hk))
        SendLevel(0)
    }

    static Test_01_Starts() {
        E2E_Tests.Dir := A_Temp "\hotkit-e2e-" A_TickCount
        E2E_Tests.Probe := E2E_Tests.Dir "\probe.txt"
        DirCreate(E2E_Tests.Dir "\plugins")
        FileCopy(A_ScriptDir "\fixture\plugins\Probe.ahk", E2E_Tests.Dir "\plugins\Probe.ahk")
        E2E_Tests.WriteConfig()
        Run('"' A_AhkPath '" /ErrorStdOut "' E2E_Tests.Main '" --config-dir "' E2E_Tests.Dir '" --exit-after 120000', , , &pid)
        E2E_Tests.Pid := pid
        ; First start writes the plugin stub and reloads itself, then reports ready.
        E2E_Tests.WaitFor("ready")
    }

    static Test_02_SimpleBinding() {
        E2E_Tests.Press(">^>!F20")
        E2E_Tests.WaitFor("simple")
    }

    static Test_03_GroupToggle() {
        E2E_Tests.Press(">^>!F19")
        E2E_Tests.WaitFor("grouped", 1)
        E2E_Tests.Press(">^>!F18")
        Sleep(300)
        E2E_Tests.Press(">^>!F19")
        Sleep(800)
        Assert.Equal(1, E2E_Tests.Count("grouped"), "disabled group must not fire")
        E2E_Tests.Press(">^>!F18")
        Sleep(1500)
        E2E_Tests.Press(">^>!F19")
        E2E_Tests.WaitFor("grouped", 2)
    }

    static Test_04_Gestures() {
        E2E_Tests.Press(">^>!F17")
        E2E_Tests.WaitFor("tap")
        Sleep(600)
        E2E_Tests.Press(">^>!F17")
        Sleep(80)
        E2E_Tests.Press(">^>!F17")
        E2E_Tests.WaitFor("doubleTap")
        Sleep(600)
        Assert.Equal(1, E2E_Tests.Count("tap"), "double tap must not also fire tap")
    }

    static Test_05_ShortcutOverlay() {
        win := "Keyboard Shortcuts ahk_pid " E2E_Tests.AppPid()
        DetectHiddenWindows(false)
        E2E_Tests.Press(">^>!F16")
        Assert.True(WinWait(win, , 10), "overlay did not open")
        total := ListViewGetContent("Count", "SysListView321", win)
        Assert.Equal(6, Integer(total), "one row per binding")
        ControlSetText("gesture", "Edit1", win)
        Sleep(300)
        Assert.Equal(1, Integer(ListViewGetContent("Count", "SysListView321", win)), "filter narrows rows")
        rows := ListViewGetContent("", "SysListView321", win)
        Assert.Contains(rows, "RCtrl+RAlt+F17")
        E2E_Tests.Press(">^>!F16")
        Assert.True(WinWaitClose(win, , 10), "overlay did not close")
    }

    static Test_06_ConfigReload() {
        E2E_Tests.WriteConfig(', { "keys": ">^>!F14", "action": "probe.mark", "args": ["reloaded"] }')
        ; The watcher polls every 2s and reloads; the probe logs ready again.
        E2E_Tests.WaitFor("ready", 2)
        E2E_Tests.Press(">^>!F14")
        E2E_Tests.WaitFor("reloaded")
    }

    static Test_07_ExitAction() {
        pid := E2E_Tests.AppPid()
        Assert.True(ProcessExist(pid), "app should be running before exit")
        E2E_Tests.Press(">^>!F15")
        ProcessWaitClose(pid, 10)
        Assert.False(ProcessExist(pid), "app did not exit")
    }

    static Cleanup() {
        for pid in [E2E_Tests.Pid, E2E_Tests.AppPid()] {
            if (pid && ProcessExist(pid))
                ProcessClose(pid)
        }
        try DirDelete(E2E_Tests.Dir, true)
    }
}

#Include %A_ScriptDir%\..\..\src\Lib\HotkeyText.ahk

OnExit((*) => E2E_Tests.Cleanup())
TestRunner.Add(E2E_Tests)
TestRunner.Run()
