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
    static WindowsPid := 0
    static Main := A_ScriptDir "\..\..\src\Main.ahk"

    static WriteConfig(extra := "") {
        text := FileRead(A_ScriptDir "\fixture\config.template.json", "UTF-8")
        text := StrReplace(text, "{{PROBE}}", StrReplace(E2E_Tests.Probe, "\", "\\"))
        text := StrReplace(text, "{{AHK}}", StrReplace(A_AhkPath, "\", "\\"))
        text := StrReplace(text, "{{FIXTURE}}", StrReplace(A_ScriptDir "\fixture", "\", "\\"))
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

    static UnderWine() {
        ntdll := DllCall("GetModuleHandle", "str", "ntdll", "ptr")
        return !!DllCall("GetProcAddress", "ptr", ntdll, "astr", "wine_get_version", "ptr")
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
        Run('"' A_AhkPath '" /ErrorStdOut "' E2E_Tests.Main '" --config-dir "' E2E_Tests.Dir '" --exit-after 120000 --allow-virtualized', , , &pid)
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
        Assert.Equal(14, Integer(total), "one row per binding")
        ControlSetText("gesture", "Edit1", win)
        Sleep(300)
        Assert.Equal(1, Integer(ListViewGetContent("Count", "SysListView321", win)), "filter narrows rows")
        rows := ListViewGetContent("", "SysListView321", win)
        Assert.Contains(rows, "RCtrl+RAlt+F17")
        E2E_Tests.Press(">^>!F16")
        Assert.True(WinWaitClose(win, , 10), "overlay did not close")
    }

    ; Hiding and showing an app with the same key must bring back the window that
    ; was focused last, not whichever of its windows is on top.
    static Test_05b_AppToggleReturnsToLastWindow() {
        Run('"' A_AhkPath '" "' A_ScriptDir '\fixture\Windows.ahk"', , , &pid)
        E2E_Tests.WindowsPid := pid
        a := "hotkit-e2e-win A", b := "hotkit-e2e-win B", other := "hotkit-e2e-other"
        for title in [a, b, other]
            Assert.True(WinWait(title, , 10), title " did not open")
        for title in [b, a] {
            WinActivate(title)
            WinWaitActive(title, , 5)
            Sleep(300)
        }
        hwndA := WinExist(a)
        E2E_Tests.Press(">^>!F13")
        Sleep(800)
        Assert.Equal(-1, WinGetMinMax(hwndA), "toggle should minimize the active window")
        Assert.NotEqual(WinExist(b), WinExist("A"), "hiding the app must not focus its other window")
        WinActivate(other)
        WinWaitActive(other, , 5)
        Sleep(300)
        E2E_Tests.Press(">^>!F13")
        Sleep(800)
        Assert.Equal(hwndA, WinExist("A"), "toggle should restore the window focused last")
    }

    ; A quick window hidden by its key must come back when activated another way
    ; (taskbar button, Alt+Tab); WinActivate raises the same shell event.
    ; Wine never delivers shell-hook messages, so this only runs on Windows.
    static Test_05c_HiddenQuickWindowRevealedOnActivate() {
        if E2E_Tests.UnderWine()
            return
        qw := "hotkit-e2e-qw"
        Assert.True(WinWait(qw, , 10), "quick window fixture did not open")
        hwnd := WinExist(qw)
        WinActivate(hwnd)
        WinWaitActive(hwnd, , 5)
        Sleep(300)
        E2E_Tests.Press(">^>!F12")
        Sleep(800)
        Assert.Equal(0, WinGetTransparent(hwnd), "toggle should hide the active quick window")
        WinActivate(hwnd)
        Sleep(1000)
        alpha := WinGetTransparent(hwnd)
        Assert.True(alpha = "" || alpha = 255, "activated quick window should be visible again, alpha=" alpha)
        Assert.Equal(0, WinGetExStyle(hwnd) & 0x20, "activated quick window should accept clicks again")
    }

    ; Apps that "close" to the tray only hide their window. The toggle key must
    ; bring it back through the launch command, not fail on the hidden window.
    static Test_05d_QuickWindowClosedToTrayComesBack() {
        qw := "hotkit-e2e-qw"
        hwnd := WinExist(qw)
        Assert.True(hwnd, "quick window fixture is not open")
        ; Hide and show it once with the key so hotkit is managing it.
        WinActivate(hwnd)
        WinWaitActive(hwnd, , 5)
        Sleep(300)
        E2E_Tests.Press(">^>!F12")
        Sleep(500)
        E2E_Tests.Press(">^>!F12")
        Assert.True(WinWaitActive("ahk_id " hwnd, , 5), "toggle should show the quick window")
        Sleep(300)
        WinHide(hwnd)
        Sleep(300)
        E2E_Tests.Press(">^>!F12")
        Assert.True(WinWaitActive("ahk_id " hwnd, , 10), "toggle should show and focus the hidden window again")
        alpha := WinGetTransparent(hwnd)
        Assert.True(alpha = "" || alpha = 255, "window should be opaque, alpha=" alpha)
    }

    ; Z-order keys restack the active window but never take focus from it.
    ; The test arranges the fixture windows itself: A and B overlap, "other"
    ; overlaps neither. Other desktop windows may sit anywhere in the stack, so
    ; each step starts from an order where the fixture windows are adjacent.
    static Test_05e_ZOrderKeepsFocus() {
        a := "hotkit-e2e-win A", b := "hotkit-e2e-win B", other := "hotkit-e2e-other"
        if (!WinExist(a) || !WinExist(b) || !WinExist(other)) {
            Run('"' A_AhkPath '" "' A_ScriptDir '\fixture\Windows.ahk"', , , &pid)
            E2E_Tests.WindowsPid := pid
        }
        for title in [a, b, other]
            Assert.True(WinWait(title, , 10), title " did not open")
        hwndA := WinExist(a), hwndB := WinExist(b), hwndO := WinExist(other)
        WinMove(100, 100, 300, 200, hwndA)
        WinMove(300, 150, 300, 200, hwndB)
        WinMove(800, 100, 200, 200, hwndO)
        handles := [hwndA, hwndB, hwndO]
        order := () => E2E_Tests.StackOrder(handles)
        arrange(letters) {
            byName := Map("A", hwndA, "B", hwndB, "O", hwndO)
            prev := 0
            for name in StrSplit(letters) {
                hwnd := byName[name]
                if (!prev)
                    WinMoveTop(hwnd)
                else
                    DllCall("user32\SetWindowPos", "ptr", hwnd, "ptr", prev, "int", 0, "int", 0,
                        "int", 0, "int", 0, "uint", 0x13)
                prev := hwnd
            }
            if (WinExist("A") != hwndA) {
                WinActivate(hwndA)
                WinWaitActive(hwndA, , 5)
            }
            Sleep(300)
            Assert.Equal(letters, order(), "arrange " letters)
        }
        step(hk, expected, msg) {
            E2E_Tests.Press(hk)
            Sleep(500)
            Assert.Equal(expected, order(), msg)
            Assert.Equal(hwndA, WinExist("A"), msg ": focus must stay on the window")
        }
        arrange("ABO")
        step(">^>!F11", "BAO", "send backward steps behind the overlapping window")
        arrange("BOA")
        step(">^>!F9", "ABO", "bring forward skips windows that do not overlap")
        step(">^>!F10", "BOA", "send to back goes behind every window")
        step(">^>!F8", "ABO", "bring to front")

        ; A window whose owner is hidden (as for many app and AHK GUI windows)
        ; must move itself, since the owner is not in the visible stack.
        owner := Gui()
        owned := Gui("+Owner" owner.Hwnd " +E0x40000", "hotkit-e2e-owned") ; WS_EX_APPWINDOW
        owned.Show("x150 y150 w200 h100")
        try {
            WinActivate(owned.Hwnd)
            WinWaitActive(owned.Hwnd, , 5)
            Sleep(300)
            E2E_Tests.Press(">^>!F10")
            Sleep(500)
            list := WinGetList()
            pos := Map()
            for i, hwnd in list
                pos[hwnd] := i
            Assert.True(pos[owned.Hwnd] > pos[hwndA] && pos[owned.Hwnd] > pos[hwndB],
                "window with a hidden owner should go to the back: " pos[owned.Hwnd] " A=" pos[hwndA] " B=" pos[hwndB] " active=" WinExist("A") " owned=" owned.Hwnd " n=" list.Length)
            Assert.Equal(owned.Hwnd, WinExist("A"), "owned window keeps focus")
            ; It is listed in Alt+Tab (WS_EX_APPWINDOW), so others stack around it.
            WinActivate(hwndA)
            WinWaitActive(hwndA, , 5)
            Sleep(300)
            E2E_Tests.Press(">^>!F10")
            Sleep(500)
            list := WinGetList()
            for i, hwnd in list
                pos[hwnd] := i
            Assert.True(pos[hwndA] > pos[owned.Hwnd], "send to back should pass an owned app window")
        } finally {
            owned.Destroy()
            owner.Destroy()
        }

        ; A dialog that sticks out of its visible owner steps behind a window
        ; it overlaps even when the owner doesn't overlap that window.
        WinMoveTop(hwndA)  ; WinActivate alone may not raise it on Windows
        main := Gui(, "hotkit-e2e-main")
        main.Show("x100 y420 w200 h100")
        dialog := Gui("+Owner" main.Hwnd, "hotkit-e2e-dialog")
        dialog.Show("x150 y250 w200 h100")
        try {
            WinActivate(dialog.Hwnd)
            WinWaitActive(dialog.Hwnd, , 5)
            Sleep(300)
            E2E_Tests.Press(">^>!F11")
            Sleep(500)
            pos := Map()
            for i, hwnd in WinGetList()
                pos[hwnd] := i
            Assert.True(pos[dialog.Hwnd] > pos[hwndA], "dialog should step behind the window it overlaps: "
                E2E_Tests.DescribeStack())
            Assert.True(pos[dialog.Hwnd] < pos[main.Hwnd], "dialog stays above its owner")
            Assert.Equal(dialog.Hwnd, WinExist("A"), "dialog keeps focus")
        } finally {
            dialog.Destroy()
            main.Destroy()
        }

        ; Outside a layer each cycle press is its own session, so two presses
        ; toggle between the top two windows, like tapping Alt+Tab.
        arrange("ABO")
        E2E_Tests.Press(">^>!F7")
        Assert.True(WinWaitActive("ahk_id " hwndB, , 3), "cycle next focuses the window under A")
        Sleep(300)
        Assert.Equal("BAO", order(), "only the selected window moves")
        E2E_Tests.Press(">^>!F7")
        Assert.True(WinWaitActive("ahk_id " hwndA, , 3), "a second press toggles back to A")
        Sleep(300)
        Assert.Equal("ABO", order(), "toggling back restores the order")

        ; A held-key session keeps the snapshot: each step raises only the
        ; selection and puts the previous one back in place.
        arrange("ABO")
        session := WindowUtil.CycleSnapshot()
        steps := [["next", hwndB, "BAO"], ["next", hwndO, "OAB"], ["previous", hwndB, "BAO"], ["previous", hwndA, "ABO"]]
        for st in steps {
            WindowUtil.CycleStep(session, st[1])
            Assert.True(WinWaitActive("ahk_id " st[2], , 3), "session " st[1] " " A_Index " focus")
            Sleep(300)
            Assert.Equal(st[3], order(), "session " st[1] " " A_Index " order")
        }

        ; From A's modal-style owned dialog, next leaves the app instead of
        ; landing on A (whose dialog would take focus right back).
        dialog := Gui("+Owner" hwndA, "hotkit-e2e-dialog")
        dialog.Show("x150 y150 w200 h100")
        try {
            WinWaitActive(dialog.Hwnd, , 5)
            Sleep(300)
            E2E_Tests.Press(">^>!F7")
            Assert.True(WinWaitActive("ahk_id " hwndB, , 3), "cycle next from A's dialog focuses B")
        } finally {
            dialog.Destroy()
        }
    }

    ; Visible top-level windows front to back, for failure messages.
    static DescribeStack() {
        out := ""
        for hwnd in WinGetList() {
            try {
                WinGetPos(&x, &y, &w, &h, hwnd)
                out .= "`n    " Format("0x{:X}", hwnd) " " WinGetClass(hwnd) " '" SubStr(WinGetTitle(hwnd), 1, 30) "' "
                    . x "," y " " w "x" h " ex=" Format("0x{:X}", WinGetExStyle(hwnd))
                    . " owner=" Format("0x{:X}", DllCall("user32\GetWindow", "ptr", hwnd, "uint", 4, "ptr"))
            }
        }
        return out
    }

    ; Letters A/B/O for the given windows, front to back.
    static StackOrder(handles) {
        names := Map(handles[1], "A", handles[2], "B", handles[3], "O")
        out := ""
        for hwnd in WinGetList()
            out .= names.Has(hwnd) ? names[hwnd] : ""
        return out
    }

    static Test_06_ConfigReload() {
        E2E_Tests.WriteConfig(', { "keys": ">^>!F14", "action": "probe.mark", "args": ["reloaded"] }')
        ; The watcher polls every 2s and reloads; the probe logs ready again.
        E2E_Tests.WaitFor("ready", 2)
        E2E_Tests.Press(">^>!F14")
        E2E_Tests.WaitFor("reloaded")
    }

    static WriteRaw(text) {
        f := FileOpen(E2E_Tests.Dir "\config.json", "w", "UTF-8-RAW")
        f.Write(text)
        f.Close()
    }

    static LogText() => FileExist(E2E_Tests.Dir "\hotkit.log") ? FileRead(E2E_Tests.Dir "\hotkit.log", "UTF-8") : ""

    static Test_07_HalfWrittenConfigWaits() {
        ; A save in progress must not be read: start a write, finish it shortly after.
        E2E_Tests.WriteRaw('{ "bindings": [')
        Sleep(300)
        E2E_Tests.WriteConfig()
        E2E_Tests.WaitFor("ready", 3)
        Assert.False(InStr(E2E_Tests.LogText(), "not applied"), "partial write was read: " E2E_Tests.LogText())
    }

    static Test_08_BrokenConfigKeepsRunning() {
        pid := E2E_Tests.AppPid()
        E2E_Tests.WriteRaw('{ "bindings": [')
        start := A_TickCount
        while (!InStr(E2E_Tests.LogText(), "not applied") && A_TickCount - start < 15000)
            Sleep(200)
        Assert.True(InStr(E2E_Tests.LogText(), "config change not applied"), "log: " E2E_Tests.LogText())
        Assert.True(ProcessExist(pid), "app must keep running on a broken config")
        Assert.Equal(3, E2E_Tests.Count("ready"), "broken config must not restart the app")
        E2E_Tests.WriteConfig()
        E2E_Tests.WaitFor("ready", 4)
    }

    static Test_09_ExitAction() {
        pid := E2E_Tests.AppPid()
        Assert.True(ProcessExist(pid), "app should be running before exit")
        E2E_Tests.Press(">^>!F15")
        ProcessWaitClose(pid, 10)
        Assert.False(ProcessExist(pid), "app did not exit")
    }

    static Cleanup() {
        for pid in [E2E_Tests.Pid, E2E_Tests.AppPid(), E2E_Tests.WindowsPid] {
            if (pid && ProcessExist(pid))
                ProcessClose(pid)
        }
        try DirDelete(E2E_Tests.Dir, true)
    }
}

#Include %A_ScriptDir%\..\..\src\Lib\HotkeyText.ahk
#Include %A_ScriptDir%\..\..\src\Lib\WindowUtil.ahk

OnExit((*) => E2E_Tests.Cleanup())
TestRunner.Add(E2E_Tests)
TestRunner.Run()
