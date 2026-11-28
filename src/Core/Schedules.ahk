#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\..\Lib\Cron.ahk
#Include %A_LineFile%\..\ActionRegistry.ahk
#Include %A_LineFile%\..\Config.ahk

; Runs actions on a schedule: cron expressions, fixed intervals, and events
; such as startup, exit, lock, unlock, sleep, resume, and idle.
;
;   "schedules": [
;     { "name": "evening", "cron": "0 19 * * *", "action": "theme.set", "args": ["dark"], "catchUp": true },
;     { "on": ["unlock", "resume"], "action": "brightness.set", "args": [70] },
;     { "every": "30m", "action": "myPlugin.sync", "machines": ["WORKPC"] }
;   ]
;
; A schedule needs an action and at least one of cron, every, or on; it runs
; whenever any of them fires. Plugins add schedules from code with
; Schedules.Add(map) in their init, and react to events with
; Schedules.On("lock", fn).
class Schedules {
    static Events := ["startup", "reload", "exit", "lock", "unlock", "sleep", "resume", "idle", "active",
        "pluggedIn", "unplugged", "remoteConnect", "remoteDisconnect"]
    static Keys := ["name", "description", "action", "args", "cron", "every", "on", "delay", "idleAfter",
        "catchUp", "machines", "enabled"]
    ; At most ~24.8 days: SetTimer periods are 32-bit milliseconds.
    static MaxEveryMs := 24 * 86400000
    static DefaultIdleMs := 600000
    static IdlePollMs := 5000
    static specs := []
    static problems := []
    ; Test seams: Runner(spec, trigger) replaces running the action.
    static Runner := ""
    static Machine := A_ComputerName
    ; Set by App.Restart so a reload doesn't count as exit.
    static Restarting := false
    static _handlers := Map()
    static _timers := []
    static _lastTick := ""
    static _acLine := ""
    static _started := false
    static _tickFn := (*) => Schedules._TimerTick()
    static _idleFn := (*) => Schedules.PollIdle(A_TimeIdlePhysical)

    static Reset(problems := "") {
        Schedules.Stop()
        Schedules.specs := []
        Schedules.problems := problems is Array ? problems : []
        Schedules._handlers := Map()
        Schedules._handlers.CaseSense := "Off"
        Schedules._lastTick := ""
        Schedules._handlerIdle := false
    }

    ; Adds the "schedules" list from config.
    static LoadConfig(cfg) {
        raw := cfg.Get("schedules", [])
        if !(raw is Array) {
            Schedules.problems.Push("schedules: must be a list.")
            return
        }
        for i, item in raw
            Schedules.Add(item, "schedules[" i "]")
    }

    ; Normalizes and validates one schedule. Returns the spec, or "" when it
    ; is disabled, belongs to another machine, or has a problem (reported).
    static Add(raw, source := "plugin") {
        if !(raw is Map) {
            Schedules.problems.Push(source ": schedule must be an object.")
            return ""
        }
        label := source
        try {
            name := MapGet(raw, "name", "")
            if !(name is String)
                throw ValueError("'name' must be a string.")
            if (name != "")
                label := source " (" name ")"
            for key in raw {
                if !Schedules._Includes(Schedules.Keys, key)
                    throw ValueError("unknown field '" key "'.")
            }
            if (raw.Has("enabled") && !raw["enabled"])
                return ""
            if (raw.Has("machines") && !Schedules.MachineMatches(raw["machines"], Schedules.Machine))
                return ""
            if !raw.Has("action")
                throw ValueError("needs 'action'.")
            ref := ActionRegistry.ParseRef(raw)
            spec := {
                name: name != "" ? name : source,
                source: source,
                description: MapGet(raw, "description", ""),
                action: ref.action,
                args: ref.args,
                crons: [],
                next: [],
                every: 0,
                events: Map(),
                delay: 0,
                idleAfter: Schedules.DefaultIdleMs,
                idle: false,
                catchUp: !!MapGet(raw, "catchUp", false),
            }
            spec.events.CaseSense := "Off"
            for text in Schedules._List(raw, "cron")
                spec.crons.Push(Cron.Parse(text))
            for expr in spec.crons {
                if (expr.Next(A_Now) = "")
                    throw ValueError("cron '" expr.text "' never matches a real date.")
            }
            if raw.Has("every") {
                spec.every := Schedules.ParseDuration(raw["every"], "every")
                if (spec.every > Schedules.MaxEveryMs)
                    throw ValueError("'every' can be at most 24 days.")
            }
            for event in Schedules._List(raw, "on")
                spec.events[Schedules.EventName(event)] := true
            if (!spec.crons.Length && !spec.every && !spec.events.Count)
                throw ValueError("needs 'cron', 'every', or 'on'.")
            if (spec.catchUp && !spec.crons.Length)
                throw ValueError("'catchUp' needs 'cron'.")
            if raw.Has("delay") {
                spec.delay := Schedules.ParseDuration(raw["delay"], "delay")
                if (!spec.events.Count)
                    throw ValueError("'delay' applies to 'on' events; this schedule has none.")
                for event in ["exit", "sleep"] {
                    if spec.events.Has(event)
                        throw ValueError("'delay' can't be used with '" event "': Hotkit or Windows won't wait.")
                }
            }
            if raw.Has("idleAfter") {
                if (!spec.events.Has("idle") && !spec.events.Has("active"))
                    throw ValueError("'idleAfter' needs 'on' to include 'idle' or 'active'.")
                spec.idleAfter := Schedules.ParseDuration(raw["idleAfter"], "idleAfter")
                if (spec.idleAfter < 10000)
                    throw ValueError("'idleAfter' must be at least 10s.")
            }
            for other in Schedules.specs {
                if (other.name = spec.name)
                    throw ValueError("another schedule is already named '" spec.name "'.")
            }
        } catch as e {
            Schedules.problems.Push(label ": " e.Message)
            return ""
        }
        Schedules.specs.Push(spec)
        return spec
    }

    ; Reports schedules whose action doesn't exist. Call after plugins load.
    static Validate() {
        for spec in Schedules.specs {
            if !ActionRegistry.Has(spec.action)
                Schedules.problems.Push(spec.source " (" spec.name "): unknown action '" spec.action "'.")
        }
    }

    ; Plugins: Schedules.On("unlock", (event) => ...). Runs alongside schedules.
    static On(event, fn) {
        name := Schedules.EventName(event)
        if !HasMethod(fn)
            throw TypeError("Schedules.On: handler for '" name "' is not callable.")
        if !Schedules._handlers.Has(name)
            Schedules._handlers[name] := []
        Schedules._handlers[name].Push(fn)
    }

    ; ---------------- Parsing                       ------------------------------

    ; "90s", "15m", "2h", "1d", "1h30m" -> milliseconds. Throws ValueError.
    static ParseDuration(value, field := "duration") {
        text := value is String ? StrLower(StrReplace(value, " ")) : ""
        if (text = "" || !RegExMatch(text, "^(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$", &m))
            throw ValueError("'" field "' must be a duration such as '90s', '15m', '2h', or '1h30m'.")
        ms := ((m[1] = "" ? 0 : Integer(m[1])) * 86400
            + (m[2] = "" ? 0 : Integer(m[2])) * 3600
            + (m[3] = "" ? 0 : Integer(m[3])) * 60
            + (m[4] = "" ? 0 : Integer(m[4]))) * 1000
        if (ms <= 0)
            throw ValueError("'" field "' must be longer than zero.")
        return ms
    }

    ; Canonical event name, case-insensitive. Throws ValueError.
    static EventName(event) {
        if (event is String) {
            for name in Schedules.Events {
                if (name = event)
                    return name
            }
        }
        list := ""
        for name in Schedules.Events
            list .= (A_Index = 1 ? "" : ", ") name
        throw ValueError("unknown event '" (IsObject(event) ? "{…}" : event) "'; use one of: " list ".")
    }

    static MachineMatches(machines, machine) {
        if (machines is String)
            machines := [machines]
        if !(machines is Array) || !machines.Length
            throw ValueError("'machines' must be a computer name or a list of them.")
        for m in machines {
            if !(m is String)
                throw ValueError("'machines' must be a computer name or a list of them.")
            if (m = machine)
                return true
        }
        return false
    }

    ; WM_WTSSESSION_CHANGE wParam -> event name, or "".
    static SessionEvent(code) {
        switch code {
            case 3: return "remoteConnect"
            case 4: return "remoteDisconnect"
            case 7: return "lock"
            case 8: return "unlock"
        }
        return ""
    }

    ; WM_POWERBROADCAST wParam -> "sleep", "resume", "power" (power source
    ; may have changed), or "". Resume uses PBT_APMRESUMEAUTOMATIC, which
    ; Windows always sends, and ignores PBT_APMRESUMESUSPEND so it runs once.
    static PowerEvent(code) {
        switch code {
            case 0x4: return "sleep"
            case 0x12: return "resume"
            case 0xA: return "power"
        }
        return ""
    }

    ; AC line status before and after (0 battery, 1 AC, 255 unknown).
    static PowerSourceEvent(before, after) {
        if (before = 0 && after = 1)
            return "pluggedIn"
        if (before = 1 && after = 0)
            return "unplugged"
        return ""
    }

    ; ---------------- Running                       ------------------------------

    ; Starts timers and event watchers (run mode), then fires startup or reload.
    static Start(reloaded := false) {
        Schedules.Stop()
        Schedules._started := true
        now := A_Now
        anyCron := false
        for spec in Schedules.specs {
            spec.next := []
            for expr in spec.crons
                spec.next.Push(expr.Next(now))
            anyCron := anyCron || spec.crons.Length
            if (spec.every) {
                fn := Schedules._RunLater.Bind(Schedules, spec, "every", 0)
                SetTimer(fn, spec.every)
                Schedules._timers.Push(fn)
            }
        }
        if (anyCron) {
            Schedules._lastTick := SubStr(now, 1, 12)
            Schedules._ArmTick()
        }
        if Schedules._Uses(["lock", "unlock", "remoteConnect", "remoteDisconnect"]) {
            OnMessage(0x02B1, Schedules._OnSession)
            if !DllCall("wtsapi32\WTSRegisterSessionNotification", "Ptr", A_ScriptHwnd, "UInt", 0)
                Schedules.problems.Push("schedules: couldn't watch for lock and unlock (error " A_LastError ").")
        }
        if Schedules._Uses(["sleep", "resume", "pluggedIn", "unplugged"]) || anyCron {
            Schedules._acLine := Schedules.ReadAcLine()
            OnMessage(0x0218, Schedules._OnPower)
        }
        if Schedules._Uses(["idle", "active"])
            SetTimer(Schedules._idleFn, Schedules.IdlePollMs)
        if Schedules._Uses(["exit"])
            OnExit(Schedules._OnExit)
        Schedules.Fire(reloaded ? "reload" : "startup")
    }

    static Stop() {
        for fn in Schedules._timers
            try SetTimer(fn, 0)
        Schedules._timers := []
        try SetTimer(Schedules._tickFn, 0)
        try SetTimer(Schedules._idleFn, 0)
        if (Schedules._started) {
            OnMessage(0x02B1, Schedules._OnSession, 0)
            OnMessage(0x0218, Schedules._OnPower, 0)
            OnExit(Schedules._OnExit, 0)
            try DllCall("wtsapi32\WTSUnRegisterSessionNotification", "Ptr", A_ScriptHwnd)
            Schedules._started := false
        }
    }

    ; Runs every schedule and handler for an event.
    static Fire(event) {
        for spec in Schedules.specs {
            if spec.events.Has(event)
                Schedules._RunLater(spec, event, spec.delay)
        }
        if Schedules._handlers.Has(event) {
            for fn in Schedules._handlers[event] {
                try {
                    fn.Call(event)
                } catch as e {
                    StatusLog.Warn("schedules: " event " handler failed: " e.Message)
                }
            }
        }
    }

    ; Runs the schedules whose cron times have come. `now` is YYYYMMDDHHMISS.
    ; A time that passed while the PC was asleep (more than a minute ago) runs
    ; once if the schedule sets catchUp, and is skipped otherwise.
    static Tick(now := A_Now) {
        minute := SubStr(now, 1, 12)
        if (minute = Schedules._lastTick)
            return
        clockBack := Schedules._lastTick != "" && minute < Schedules._lastTick
        Schedules._lastTick := minute
        for spec in Schedules.specs {
            due := "", missed := false
            for i, expr in spec.crons {
                if (clockBack) {
                    ; The clock moved back: start over from the new time.
                    spec.next[i] := expr.Next(now)
                    continue
                }
                at := spec.next[i]
                if (at = "" || SubStr(at, 1, 12) > minute)
                    continue
                if (SubStr(at, 1, 12) = minute)
                    due := "cron"
                else
                    missed := true
                spec.next[i] := expr.Next(now)
            }
            if (due = "" && missed) {
                if (spec.catchUp)
                    due := "cron (catch-up)"
                else
                    StatusLog.Info("schedule " spec.name ": skipped a time missed while the PC was asleep or busy")
            }
            if (due != "")
                Schedules.Run(spec, due)
        }
    }

    ; Fires idle and active for each schedule's own idleAfter. idleMs is how
    ; long the keyboard and mouse have been untouched.
    static PollIdle(idleMs) {
        for spec in Schedules.specs {
            if (!spec.events.Has("idle") && !spec.events.Has("active"))
                continue
            isIdle := idleMs >= spec.idleAfter
            if (isIdle = spec.idle)
                continue
            spec.idle := isIdle
            event := isIdle ? "idle" : "active"
            if spec.events.Has(event)
                Schedules._RunLater(spec, event, spec.delay)
        }
        Schedules._HandlersFor(idleMs)
    }

    ; Plugin handlers for idle/active use the default idle time.
    static _handlerIdle := false
    static _HandlersFor(idleMs) {
        isIdle := idleMs >= Schedules.DefaultIdleMs
        if (isIdle = Schedules._handlerIdle)
            return
        Schedules._handlerIdle := isIdle
        event := isIdle ? "idle" : "active"
        if Schedules._handlers.Has(event) {
            for fn in Schedules._handlers[event]
                try fn.Call(event)
        }
    }

    ; Runs a schedule's action now (the schedule.run action).
    static RunNow(name) {
        for spec in Schedules.specs {
            if (spec.name = name)
                return Schedules.Run(spec, "manual")
        }
        throw ValueError("No schedule named '" name "'.")
    }

    static Run(spec, trigger) {
        StatusLog.Info("schedule " spec.name ": " trigger " -> " spec.action)
        if HasMethod(Schedules.Runner)
            return Schedules.Runner.Call(spec, trigger)
        return ActionRegistry.SafeInvoke(spec.action, spec.args)
    }

    static _RunLater(spec, trigger, delayMs, *) {
        if (delayMs > 0)
            SetTimer((*) => Schedules.Run(spec, trigger), -delayMs)
        else
            Schedules.Run(spec, trigger)
    }

    ; ---------------- Windows events                ------------------------------

    static _OnSession := (wParam, lParam, msg, hwnd) => Schedules._Session(wParam)
    static _OnPower := (wParam, lParam, msg, hwnd) => Schedules._Power(wParam)
    ; Non-zero would cancel the exit.
    static _OnExit := (reason, code) => (Schedules._Exit(), 0)

    static _Session(code) {
        event := Schedules.SessionEvent(code)
        if (event != "")
            Schedules.Fire(event)
    }

    static _Power(code) {
        event := Schedules.PowerEvent(code)
        if (event = "power") {
            line := Schedules.ReadAcLine()
            event := Schedules.PowerSourceEvent(Schedules._acLine, line)
            Schedules._acLine := line
        }
        if (event = "")
            return
        Schedules.Fire(event)
        if (event = "resume" && Schedules._lastTick != "")
            Schedules._TimerTick()
    }

    static _Exit() {
        if (!Schedules.Restarting)
            Schedules.Fire("exit")
    }

    ; 0 on battery, 1 on AC, 255 unknown.
    static ReadAcLine() {
        status := Buffer(12, 0)
        if !DllCall("GetSystemPowerStatus", "Ptr", status)
            return 255
        return NumGet(status, 0, "UChar")
    }

    static _TimerTick() {
        Schedules.Tick(A_Now)
        Schedules._ArmTick()
    }

    ; One-shot timer for just after the next minute starts.
    static _ArmTick() {
        ms := (60 - A_Sec) * 1000 - A_MSec + 100
        SetTimer(Schedules._tickFn, -Max(200, Min(ms, 60100)))
    }

    static _Uses(events) {
        for event in events {
            if Schedules._handlers.Has(event)
                return true
            for spec in Schedules.specs {
                if spec.events.Has(event)
                    return true
            }
        }
        return false
    }

    static _List(raw, key) {
        if !raw.Has(key)
            return []
        value := raw[key]
        if (value is Array) {
            if !value.Length
                throw ValueError("'" key "' is an empty list.")
            return value
        }
        return [value]
    }

    static _Includes(list, value) {
        for item in list {
            if (item = value)
                return true
        }
        return false
    }
}
