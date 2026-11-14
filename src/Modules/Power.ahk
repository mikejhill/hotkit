#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\..\Lib\Toast.ahk

; Stay-awake toggles and monitors-off, using only documented Windows calls:
;
;   keepAwake     the PC doesn't go to sleep (screen may still turn off)
;   keepScreenOn  the screen stays on, and the PC stays awake
;   keepUnlocked  as keepScreenOn, and your own screen saver is paused, so an
;                 idle session doesn't lock. hotkit refuses this when a policy
;                 (Group Policy, MDM) enforces a lock; it never sends fake input.
;
; Every toggle starts off and is forgotten when hotkit exits (a config reload
; keeps it). The power requests come from SetThreadExecutionState, the same
; call PowerToys Awake uses; the screen saver is paused for this session only
; with SystemParametersInfo and is never written to the registry.
;
; Config: "modules": { "power": { "enabled": false } } removes the actions and
; tray menu.
class PowerModule {
    static Name := "power"
    static Enabled := false
    static State := { keepAwake: false, keepScreenOn: false, keepUnlocked: false }
    static MonitorsOffSince := 0
    static _savedScreenSaver := ""
    static _menu := ""
    static _exitRegistered := false
    static _watchMonitors := (*) => PowerModule._CheckMonitorsWake()

    static ES_CONTINUOUS := 0x80000000
    static ES_SYSTEM_REQUIRED := 0x1
    static ES_DISPLAY_REQUIRED := 0x2

    static Labels := Map(
        "keepAwake", "Keep &Awake (no sleep)",
        "keepScreenOn", "Keep &Screen On",
        "keepUnlocked", "Keep &Unlocked")

    static Register(cfg) {
        PowerModule.Enabled := cfg.ModuleEnabled("power", true)
        if (!PowerModule.Enabled)
            return
        reg := (id, fn, desc, params := "") => ActionRegistry.Register(id, fn,
            { module: PowerModule.Name, description: desc, params: params })
        for name, what in Map("keepAwake", "keeping the PC awake (no sleep)",
            "keepScreenOn", "keeping the screen on (and the PC awake)",
            "keepUnlocked", "keeping the session unlocked (screen on, screen saver paused)") {
            reg("power." name ".toggle", PowerModule._Bind(name, "toggle"), "Toggle " what)
            reg("power." name ".on", PowerModule._Bind(name, true), "Start " what)
            reg("power." name ".off", PowerModule._Bind(name, false), "Stop " what)
        }
        reg("power.allOff", (*) => PowerModule.AllOff(), "Turn every stay-awake toggle off")
        reg("monitors.off", (*) => PowerModule.MonitorsOff(),
            "Turn all monitors off (any input turns them back on); works while Keep Screen On is active")
    }

    static _Bind(name, value) => (*) => PowerModule.Set(name, value)

    static Start(cfg) {
        if (!PowerModule.Enabled) {
            ; A reload that disabled the module must not leave toggles to revive later.
            PowerModule.ReadHandoff()
            return
        }
        Tray.AddStatus(() => PowerModule.Summary(PowerModule.State))
        PowerModule._RegisterExit()
        handoff := PowerModule.ReadHandoff()
        if (handoff.keepAwake || handoff.keepScreenOn || handoff.keepUnlocked) {
            if (handoff.monitorsOff) {
                ; Keep the monitors off until the next input, as before the reload.
                PowerModule.MonitorsOffSince := A_TickCount
                SetTimer(PowerModule._watchMonitors, 500)
            }
            for name in ["keepAwake", "keepScreenOn", "keepUnlocked"]
                if (handoff.%name%)
                    PowerModule.Set(name, true, true)
            StatusLog.Info("power: kept across reload: " PowerModule.Summary(PowerModule.State))
        }
    }

    ; ---------------- Toggles                       ------------------------------

    ; value: true, false or "toggle". quiet skips the toast.
    static Set(name, value, quiet := false) {
        if (!PowerModule.State.HasOwnProp(name))
            throw ValueError("Unknown power toggle: " name)
        on := value = "toggle" ? !PowerModule.State.%name% : !!value
        if (on && name = "keepUnlocked") {
            reason := PowerModule.LockPolicy(PowerModule.ReadLockPolicy())
            if (reason != "") {
                StatusLog.Warn("power: keep unlocked refused: " reason)
                Toast.ShowToast({ color: "FF6060", fadeDelay: 8000 }, "Keep Unlocked not available:", reason)
                return false
            }
        }
        PowerModule.State.%name% := on
        PowerModule.Apply()
        StatusLog.Info("power: " name (on ? " on" : " off"))
        if (!quiet) {
            if (on && name = "keepUnlocked")
                Toast.ShowToast({ color: "FFB000", fadeDelay: 7000 }, "Keep Unlocked: ON",
                    "Anyone at this PC can use your session. Turn it off when you're done.")
            else
                Toast.ShowToast(, StrReplace(PowerModule.Labels[name], "&") ":", on ? "On" : "Off")
        }
        return on
    }

    static AllOff() {
        for name in ["keepAwake", "keepScreenOn", "keepUnlocked"]
            PowerModule.State.%name% := false
        PowerModule.Apply()
        StatusLog.Info("power: all off")
        Toast.ShowToast(, "Stay awake:", "All off")
    }

    ; Applies State to Windows: power request, screen saver, tray menu and tip.
    static Apply() {
        flags := PowerModule.Flags(PowerModule.State, PowerModule.MonitorsOffSince != 0)
        DllCall("SetThreadExecutionState", "UInt", flags, "UInt")
        PowerModule._ApplyScreenSaver(PowerModule.State.keepUnlocked)
        PowerModule._UpdateMenu()
        Tray.RefreshTip()
    }

    ; Pure: the SetThreadExecutionState flags for a state. While monitors are
    ; switched off on purpose the display request is dropped (so it doesn't
    ; wake them) and the PC is kept awake instead.
    static Flags(state, monitorsOff := false) {
        display := state.keepScreenOn || state.keepUnlocked
        flags := PowerModule.ES_CONTINUOUS
        if (display || state.keepAwake)
            flags |= PowerModule.ES_SYSTEM_REQUIRED
        if (display && !monitorsOff)
            flags |= PowerModule.ES_DISPLAY_REQUIRED
        return flags
    }

    ; Pure: tray tooltip suffix, "" when everything is off.
    static Summary(state) {
        if (state.keepUnlocked)
            return "keeping unlocked"
        if (state.keepScreenOn)
            return "keeping screen on"
        if (state.keepAwake)
            return "keeping awake"
        return ""
    }

    ; ---------------- Lock policy                   ------------------------------

    ; Policy values that make Windows lock an idle session. Missing values are "".
    static ReadLockPolicy() {
        read := (key, name) => PowerModule._RegRead(key, name)
        desk := "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop"
        return {
            inactivityTimeoutSecs: read("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System", "InactivityTimeoutSecs"),
            screenSaveActive: read(desk, "ScreenSaveActive"),
            screenSaverIsSecure: read(desk, "ScreenSaverIsSecure"),
            mdmMaxInactivityMinutes: read("HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\DeviceLock", "MaxInactivityTimeDeviceLock")
        }
    }

    static _RegRead(key, name) {
        try return RegRead(key, name)
        return ""
    }

    ; Pure: why an enforced lock rules out keepUnlocked, or "" when nothing is
    ; enforced. hotkit leaves an enforced lock alone.
    static LockPolicy(p) {
        isOn := (v) => v != "" && IsNumber(v) && Number(v) > 0
        if (isOn(p.inactivityTimeoutSecs))
            return "a policy locks this PC after " p.inactivityTimeoutSecs " seconds without input. Keep Screen On still works."
        if (p.HasOwnProp("mdmMaxInactivityMinutes") && isOn(p.mdmMaxInactivityMinutes))
            return "a device-management (MDM) policy locks this PC after " p.mdmMaxInactivityMinutes " minutes without input. Keep Screen On still works."
        if (isOn(p.screenSaverIsSecure) || isOn(p.screenSaveActive))
            return "a policy enforces a locking screen saver. Keep Screen On still works."
        return ""
    }

    ; Pauses (or restores) the user's own screen saver for this session only:
    ; no SPIF_UPDATEINIFILE, so the registry setting is untouched.
    static _ApplyScreenSaver(pause) {
        if (pause && PowerModule._savedScreenSaver = "") {
            active := 0
            DllCall("SystemParametersInfoW", "UInt", 0x10, "UInt", 0, "Int*", &active, "UInt", 0) ; SPI_GETSCREENSAVEACTIVE
            PowerModule._savedScreenSaver := active
            if (active)
                DllCall("SystemParametersInfoW", "UInt", 0x11, "UInt", 0, "Ptr", 0, "UInt", 0) ; SPI_SETSCREENSAVEACTIVE
        } else if (!pause && PowerModule._savedScreenSaver != "") {
            if (PowerModule._savedScreenSaver)
                DllCall("SystemParametersInfoW", "UInt", 0x11, "UInt", 1, "Ptr", 0, "UInt", 0)
            PowerModule._savedScreenSaver := ""
        }
    }

    ; ---------------- Monitors off                  ------------------------------

    ; Turns the monitors off after a short pause (so releasing the hotkey
    ; doesn't wake them). Any keyboard or mouse input turns them back on, and
    ; then Keep Screen On / Keep Unlocked take effect again.
    static MonitorsOff() {
        SetTimer(() => PowerModule._MonitorsOffNow(), -600)
    }

    static _MonitorsOffNow() {
        PowerModule.MonitorsOffSince := A_TickCount
        PowerModule.Apply()
        hwnd := DllCall("FindWindowW", "Str", "Progman", "Ptr", 0, "Ptr")
        DllCall("PostMessageW", "Ptr", hwnd ? hwnd : 0xFFFF, "UInt", 0x0112, "Ptr", 0xF170, "Ptr", 2) ; WM_SYSCOMMAND, SC_MONITORPOWER, off
        SetTimer(PowerModule._watchMonitors, 500)
    }

    static _CheckMonitorsWake() {
        if (!PowerModule.MonitorsOffSince)
            return SetTimer(PowerModule._watchMonitors, 0)
        if (PowerModule.InputSince(PowerModule.MonitorsOffSince, A_TickCount, A_TimeIdle)) {
            PowerModule.MonitorsOffSince := 0
            SetTimer(PowerModule._watchMonitors, 0)
            PowerModule.Apply()
        }
    }

    ; Pure: whether input happened after the monitors went off. The caller uses
    ; A_TimeIdle (GetLastInputInfo: keyboard and mouse, with or without hooks;
    ; any input that wakes the monitors counts). The hotkey's own key-up comes
    ; before that (MonitorsOff waits first).
    static InputSince(offAt, now, idleMs) => idleMs < now - offAt

    ; ---------------- Tray                          ------------------------------

    static TrayMenus(cfg) {
        if (!PowerModule.Enabled)
            return []
        m := Menu()
        for name in ["keepAwake", "keepScreenOn", "keepUnlocked"]
            m.Add(PowerModule.Labels[name], ActionRegistry.Callback("power." name ".toggle"))
        m.Add()
        m.Add("Turn &Monitors Off", ActionRegistry.Callback("monitors.off"))
        PowerModule._menu := m
        PowerModule._UpdateMenu()
        return [{ label: "Stay &Awake", menu: m }]
    }

    static _UpdateMenu() {
        if (!PowerModule._menu)
            return
        for name, label in PowerModule.Labels {
            try PowerModule.State.%name% ? PowerModule._menu.Check(label) : PowerModule._menu.Uncheck(label)
        }
    }

    ; ---------------- Reload handoff                ------------------------------

    ; A config reload restarts hotkit; the toggles are handed to the new
    ; process through a short-lived file so an overnight session survives a
    ; config sync. The file is named by a random token that only the
    ; replacement process receives (in its environment), so a normal launch,
    ; another checkout, or a launch after a failed reload never picks it up
    ; and starts with everything off.
    static HandoffEnv := "HOTKIT_POWER_HANDOFF"
    static HandoffDir() => A_Temp
    static HandoffFile(token) => PowerModule.HandoffDir() "\hotkit-power-handoff-" token ".ini"

    static _RegisterExit() {
        if (PowerModule._exitRegistered)
            return
        PowerModule._exitRegistered := true
        OnExit((*) => PowerModule._OnExit())
    }

    static _OnExit() => PowerModule._ApplyScreenSaver(false)

    ; Called by App.Restart just before a reload.
    static BeforeRestart() {
        if (!PowerModule.Enabled || PowerModule.Summary(PowerModule.State) = "")
            return
        token := ""
        loop 4
            token .= Format("{:08x}", Random(0, 0x7FFFFFFF))
        f := PowerModule.HandoffFile(token)
        IniWrite(A_Now, f, "power", "written")
        for name in ["keepAwake", "keepScreenOn", "keepUnlocked"]
            IniWrite(PowerModule.State.%name% ? 1 : 0, f, "power", name)
        IniWrite(PowerModule.MonitorsOffSince ? 1 : 0, f, "power", "monitorsOff")
        EnvSet(PowerModule.HandoffEnv, token)
    }

    ; Reads and removes this process's handoff (if any), and clears the token
    ; so processes hotkit launches don't inherit it. Also removes handoffs left
    ; behind by reloads that never finished.
    static ReadHandoff() {
        out := { keepAwake: false, keepScreenOn: false, keepUnlocked: false, monitorsOff: false }
        token := EnvGet(PowerModule.HandoffEnv)
        EnvSet(PowerModule.HandoffEnv)
        if (RegExMatch(token, "^[0-9a-f]{32}$")) {
            f := PowerModule.HandoffFile(token)
            if (FileExist(f)) {
                try {
                    written := IniRead(f, "power", "written", "")
                    if (PowerModule.HandoffFresh(written, A_Now)) {
                        for name in ["keepAwake", "keepScreenOn", "keepUnlocked", "monitorsOff"]
                            out.%name% := IniRead(f, "power", name, 0) = 1
                    }
                }
                try FileDelete(f)
            }
        }
        loop files PowerModule.HandoffDir() "\hotkit-power-handoff-*.ini" {
            if (!PowerModule.HandoffFresh(FileGetTime(A_LoopFileFullPath, "M"), A_Now))
                try FileDelete(A_LoopFileFullPath)
        }
        return out
    }
    ; Pure: a handoff counts only if written within the last two minutes.
    static HandoffFresh(written, now) {
        if (written = "" || !IsTime(written))
            return false
        age := DateDiff(now, written, "Seconds")
        return age >= 0 && age <= 120
    }
}
