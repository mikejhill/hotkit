#Requires AutoHotkey v2.0

; State and formatting for the Stopwatch example plugin. Callers pass the
; current tick (A_TickCount), so everything here can be unit tested.
class StopwatchClock {
    static New() => { running: false, startTick: 0, banked: 0, lapMark: 0, laps: [] }

    static Start(c, now) {
        if c.running
            return
        c.running := true
        c.startTick := now
    }

    static Pause(c, now) {
        if !c.running
            return
        c.banked += now - c.startTick
        c.running := false
    }

    static Reset(c) {
        c.running := false
        c.startTick := 0
        c.banked := 0
        c.lapMark := 0
        c.laps := []
    }

    static Elapsed(c, now) => c.banked + (c.running ? now - c.startTick : 0)

    ; Records the time since the previous lap (or since the start). No-op when nothing has elapsed.
    static Lap(c, now) {
        total := StopwatchClock.Elapsed(c, now)
        lap := total - c.lapMark
        if (lap <= 0)
            return 0
        c.laps.Push(lap)
        c.lapMark := total
        return lap
    }

    ; 65432 -> "01:05.4"; 3723400 -> "1:02:03.4"
    static Format(ms) {
        tenths := Floor(Max(0, ms) / 100)
        h := tenths // 36000
        m := Mod(tenths // 600, 60)
        s := Mod(tenths // 10, 60)
        t := Mod(tenths, 10)
        text := Format("{:02}:{:02}.{}", m, s, t)
        return h ? h ":" text : text
    }
}
