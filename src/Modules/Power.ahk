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
; keeps it). A toggle can be turned on for a number of minutes; it turns
; itself off when the time is up. The power requests come from
; SetThreadExecutionState, the same call PowerToys Awake uses; the screen
; saver is paused for this session only with SystemParametersInfo and is never
; written to the registry.
;
; Config: "modules": { "power": { "enabled": false } } removes the actions and
; tray menu.
class PowerModule {
    static Name := "power"
    static Enabled := false
    static Names := ["keepAwake", "keepScreenOn", "keepUnlocked"]
    static State := { keepAwake: false, keepScreenOn: false, keepUnlocked: false }
    ; End time (YYYYMMDDHHMISS) per toggle; "" means no time limit.
    static Until := { keepAwake: "", keepScreenOn: "", keepUnlocked: "" }
    static Durations := [30, 60, 120, 240, 480]
    static MonitorsOffSince := 0
    static _savedScreenSaver := ""
    static _menu := ""
    static _subMenus := Map()
    static _exitRegistered := false
    static _watchMonitors := (*) => PowerModule._CheckMonitorsWake()
    static _timerTick := (*) => PowerModule._CheckTimers()

    static ES_CONTINUOUS := 0x80000000
    static ES_SYSTEM_REQUIRED := 0x1
    static ES_DISPLAY_REQUIRED := 0x2

    static Labels := Map(
        "keepAwake", "Keep &Awake (no sleep)",
        "keepScreenOn", "Keep &Screen On",
        "keepUnlocked", "Keep &Unlocked")

    ; "Keep Awake", "Keep Screen On", "Keep Unlocked".
    static Title(name) => StrReplace(StrReplace(PowerModule.Labels[name], "&"), " (no sleep)")

    static Register(cfg) {
        PowerModule.Enabled := cfg.ModuleEnabled("power", true)
        if (!PowerModule.Enabled)
            return
        reg := (id, fn, desc, params := "") => ActionRegistry.Register(id, fn,
            { module: PowerModule.Name, description: desc, params: params })
        for name, what in Map("keepAwake", "the PC doesn't sleep",
            "keepScreenOn", "the screen stays on and the PC stays awake",
            "keepUnlocked", "the screen stays on and the screen saver is paused") {
            title := PowerModule.Title(name)
            reg("power." name ".toggle", PowerModule._Bind(name, "toggle"),
                "Enable or disable " title " (" what "), with an optional time limit", "[minutes]")
            reg("power." name ".on", PowerModule._Bind(name, true),
                "Enable " title " (" what "), with an optional time limit", "[minutes]")
            reg("power." name ".off", PowerModule._Bind(name, false), "Disable " title)
        }
        reg("power.allOff", (*) => PowerModule.AllOff(), "Disable Keep Awake, Keep Screen On and Keep Unlocked")
        reg("monitors.off", (*) => PowerModule.MonitorsOff(),
            "Turn all monitors off until the next input; works with Keep Screen On")
    }

    static _Bind(name, value) => (minutes := 0, *) => PowerModule.Set(name, value, false, minutes)

    static Start(cfg) {
        if (!PowerModule.Enabled) {
            ; A reload that disabled the module must not leave toggles to revive later.
            PowerModule.ReadHandoff()
            return
        }
        Tray.AddStatus(() => PowerModule.Summary(PowerModule.State, PowerModule.Until))
        PowerModule._RegisterExit()
        handoff := PowerModule.ReadHandoff()
        if (handoff.keepAwake || handoff.keepScreenOn || handoff.keepUnlocked) {
            if (handoff.monitorsOff) {
                ; Keep the monitors off until the next input, as before the reload.
                PowerModule.MonitorsOffSince := A_TickCount
                SetTimer(PowerModule._watchMonitors, 500)
            }
            for name in PowerModule.Names {
                if (handoff.%name%)
                    PowerModule.Set(name, true, true, handoff.until.%name%)
            }
            StatusLog.Info("power: kept across reload: " PowerModule.Summary(PowerModule.State, PowerModule.Until))
        }
    }

    ; ---------------- Toggles                       ------------------------------

    ; value: true, false or "toggle". quiet skips the toast. limit: minutes
    ; (0 or "" for no time limit), or an end time (YYYYMMDDHHMISS) when
    ; restoring after a reload.
    static Set(name, value, quiet := false, limit := 0) {
        if (!PowerModule.State.HasOwnProp(name))
            throw ValueError("Unknown power toggle: " name)
        on := value = "toggle" ? !PowerModule.State.%name% : !!value
        endAt := on ? PowerModule.EndTime(limit, A_Now) : ""
        if (on && name = "keepUnlocked") {
            reason := PowerModule.LockPolicy(PowerModule.ReadLockPolicy())
            if (reason != "") {
                StatusLog.Warn("power: keep unlocked refused: " reason)
                Toast.ShowToast({ color: "FF6060", fadeDelay: 8000 }, "Keep Unlocked is unavailable", reason)
                return false
            }
        }
        PowerModule.State.%name% := on
        PowerModule.Until.%name% := endAt
        PowerModule.Apply()
        StatusLog.Info("power: " name (on ? " on" (endAt != "" ? " until " endAt : "") : " off"))
        if (!quiet) {
            status := on ? PowerModule.OnText(endAt) : "Off."
            if (on && name = "keepUnlocked")
                Toast.ShowToast({ color: "FFB000", fadeDelay: 7000 }, "Keep Unlocked is on",
                    "Anyone at this PC can use your session.", status)
            else
                Toast.ShowToast(, PowerModule.Title(name), status)
        }
        return on
    }

    static AllOff() {
        for name in PowerModule.Names {
            PowerModule.State.%name% := false
            PowerModule.Until.%name% := ""
        }
        PowerModule.Apply()
        StatusLog.Info("power: all off")
        Toast.ShowToast(, "Stay Awake", "All off.")
    }

    ; Applies State to Windows: power request, screen saver, tray menu, tip and
    ; the time-limit check.
    static Apply() {
        flags := PowerModule.Flags(PowerModule.State, PowerModule.MonitorsOffSince != 0)
        DllCall("SetThreadExecutionState", "UInt", flags, "UInt")
        PowerModule._ApplyScreenSaver(PowerModule.State.keepUnlocked)
        PowerModule._UpdateMenu()
        Tray.RefreshTip()
        timed := false
        for name in PowerModule.Names
            timed := timed || PowerModule.Until.%name% != ""
        SetTimer(PowerModule._timerTick, timed ? 15000 : 0)
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

    ; Pure: tray tooltip text for the strongest toggle that is on, such as
    ; "Keep Unlocked until 2:30 AM"; "" when everything is off.
    static Summary(state, ends := "") {
        for name in ["keepUnlocked", "keepScreenOn", "keepAwake"] {
            if (state.%name%) {
                endAt := IsObject(ends) ? ends.%name% : ""
                return PowerModule.Title(name) (endAt != "" ? " until " PowerModule.Clock(endAt) : "")
            }
        }
        return ""
    }

    ; ---------------- Time limits                   ------------------------------

    ; Pure: the end time for a limit, or "" for none. limit is a number of
    ; minutes (0 or "" means no limit) or an end time (YYYYMMDDHHMISS).
    static EndTime(limit, now) {
        if (limit = "" || limit = 0)
            return ""
        if (StrLen(limit) = 14 && IsTime(limit))
            return limit
        if (!IsNumber(limit) || limit <= 0)
            throw ValueError("The time limit must be a positive number of minutes: " limit)
        return DateAdd(now, Round(limit * 60), "Seconds")
    }

    ; Pure: "On." or "On until 2:30 AM."
    static OnText(endAt) => endAt = "" ? "On." : "On until " PowerModule.Clock(endAt) "."

    static Clock(time) => FormatTime(time, "h:mm tt")

    ; Pure: the toggles whose time is up.
    static Expired(ends, now) {
        out := []
        for name in PowerModule.Names {
            endAt := ends.%name%
            if (endAt != "" && DateDiff(endAt, now, "Seconds") <= 0)
                out.Push(name)
        }
        return out
    }

    static _CheckTimers() {
        for name in PowerModule.Expired(PowerModule.Until, A_Now) {
            PowerModule.State.%name% := false
            PowerModule.Until.%name% := ""
            PowerModule.Apply()
            StatusLog.Info("power: " name " off (time limit)")
            Toast.ShowToast(, PowerModule.Title(name), "Off. The time limit ended.")
        }
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
            return "A policy locks this PC after " p.inactivityTimeoutSecs " seconds without input. Keep Screen On still works."
        if (p.HasOwnProp("mdmMaxInactivityMinutes") && isOn(p.mdmMaxInactivityMinutes))
            return "A device management (MDM) policy locks this PC after " p.mdmMaxInactivityMinutes " minutes without input. Keep Screen On still works."
        if (isOn(p.screenSaverIsSecure) || isOn(p.screenSaveActive))
            return "A policy requires a locking screen saver. Keep Screen On still works."
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

    ; Stay Awake › <toggle> › Off / On (no time limit) / For 30 minutes ... 8 hours.
    static TrayMenus(cfg) {
        if (!PowerModule.Enabled)
            return []
        m := Menu()
        PowerModule._subMenus := Map()
        for name in PowerModule.Names {
            sub := Menu()
            sub.Add("&Off", ActionRegistry.Callback("power." name ".off"))
            sub.Add("&On (no time limit)", ActionRegistry.Callback("power." name ".on"))
            sub.Add()
            for minutes in PowerModule.Durations
                sub.Add(PowerModule.DurationLabel(minutes),
                    ActionRegistry.Callback(Map("action", "power." name ".on", "args", [minutes])))
            PowerModule._subMenus[name] := sub
            m.Add(PowerModule.Labels[name], sub)
        }
        m.Add()
        m.Add("Turn All O&ff", ActionRegistry.Callback("power.allOff"))
        m.Add("Turn &Monitors Off", ActionRegistry.Callback("monitors.off"))
        PowerModule._menu := m
        PowerModule._UpdateMenu()
        return [{ label: "Stay &Awake", menu: m }]
    }

    ; Pure: "For &30 minutes", "For &1 hour", "For &2 hours".
    static DurationLabel(minutes) {
        if (Mod(minutes, 60) = 0)
            return "For &" (minutes // 60) (minutes = 60 ? " hour" : " hours")
        return "For &" minutes " minutes"
    }

    ; Checks each toggle that is on, and Off or On (no time limit) inside its
    ; submenu. A timed toggle checks neither; its end time is in the tooltip.
    static _UpdateMenu() {
        if (!PowerModule._menu)
            return
        for name in PowerModule.Names {
            on := PowerModule.State.%name%
            label := PowerModule.Labels[name]
            try on ? PowerModule._menu.Check(label) : PowerModule._menu.Uncheck(label)
            if (!PowerModule._subMenus.Has(name))
                continue
            sub := PowerModule._subMenus[name]
            try on ? sub.Uncheck("&Off") : sub.Check("&Off")
            try (on && PowerModule.Until.%name% = "") ? sub.Check("&On (no time limit)") : sub.Uncheck("&On (no time limit)")
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
        for name in PowerModule.Names {
            IniWrite(PowerModule.State.%name% ? 1 : 0, f, "power", name)
            IniWrite(PowerModule.Until.%name%, f, "power", name "Until")
        }
        IniWrite(PowerModule.MonitorsOffSince ? 1 : 0, f, "power", "monitorsOff")
        EnvSet(PowerModule.HandoffEnv, token)
    }

    ; Reads and removes this process's handoff (if any), and clears the token
    ; so processes hotkit launches don't inherit it. Also removes handoffs left
    ; behind by reloads that never finished.
    static ReadHandoff() {
        out := { keepAwake: false, keepScreenOn: false, keepUnlocked: false, monitorsOff: false,
            until: { keepAwake: "", keepScreenOn: "", keepUnlocked: "" } }
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
                        for name in PowerModule.Names {
                            endAt := IniRead(f, "power", name "Until", "")
                            limit := PowerModule.HandoffUntil(endAt, A_Now)
                            if (limit = "expired")
                                out.%name% := false ; ran out during the reload
                            else if (limit = "active")
                                out.until.%name% := endAt
                        }
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

    ; Pure: "none" (no time limit), "active" or "expired" for a handed-over end time.
    static HandoffUntil(endAt, now) {
        if (endAt = "" || StrLen(endAt) != 14 || !IsTime(endAt))
            return "none"
        return DateDiff(endAt, now, "Seconds") > 0 ? "active" : "expired"
    }

    ; Pure: a handoff counts only if written within the last two minutes.
    static HandoffFresh(written, now) {
        if (written = "" || !IsTime(written))
            return false
        age := DateDiff(now, written, "Seconds")
        return age >= 0 && age <= 120
    }
}
