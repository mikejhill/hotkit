#Requires AutoHotkey v2.0

; Five-field cron expressions, evaluated in local time.
;
;   minute hour day-of-month month day-of-week
;   expr := Cron.Parse("30 7 * * mon-fri")
;   expr.Matches(A_Now)            ; true at 07:30 on weekdays
;   expr.Next(A_Now)               ; next matching minute after A_Now (YYYYMMDDHHMI00)
;   expr.Previous(A_Now)           ; last matching minute before A_Now
;
; Each field takes *, a number or name, a range a-b, a list a,b,c and a step
; /n after * or a range ("*/15", "8-18/2"); "a/n" means a through the field's
; maximum. Months take jan-dec and days take sun-sat; 0 and 7 are both Sunday.
; Shorthands: @yearly (@annually), @monthly, @weekly, @daily (@midnight),
; @hourly. As in classic cron, when both day fields are restricted a day
; matches if either one does.
class Cron {
    static Macros := Map(
        "@yearly", "0 0 1 1 *", "@annually", "0 0 1 1 *", "@monthly", "0 0 1 * *",
        "@weekly", "0 0 * * 0", "@daily", "0 0 * * *", "@midnight", "0 0 * * *", "@hourly", "0 * * * *")
    static Months := ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    static Days := ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    ; Next() gives up after this many years (covers Feb 29 and similar).
    static SearchYears := 8

    __New(text, minutes, hours, days, months, weekdays, dayStar, weekdayStar) {
        this.text := text
        this.minutes := minutes
        this.hours := hours
        this.days := days
        this.months := months
        this.weekdays := weekdays
        this.dayStar := dayStar
        this.weekdayStar := weekdayStar
    }

    ; Throws ValueError naming the bad field.
    static Parse(text) {
        if !(text is String)
            throw ValueError("cron expression must be a string.")
        source := Trim(text)
        expanded := Cron.Macros.Has(StrLower(source)) ? Cron.Macros[StrLower(source)] : source
        fields := StrSplit(RegExReplace(Trim(expanded), "\s+", " "), " ")
        if (source = "" || fields.Length != 5)
            throw ValueError("cron expression '" source "' needs 5 fields (minute hour day month weekday), got "
                (source = "" ? 0 : fields.Length) ".")
        minutes := Cron._Field(fields[1], 0, 59, "minute")
        hours := Cron._Field(fields[2], 0, 23, "hour")
        days := Cron._Field(fields[3], 1, 31, "day of month")
        months := Cron._Field(fields[4], 1, 12, "month", Cron.Months)
        weekdays := Cron._Field(fields[5], 0, 7, "day of week", Cron.Days)
        if (weekdays.Has(7) && weekdays[7])
            weekdays[0] := true
        return Cron(source, minutes, hours, days, months, weekdays,
            SubStr(fields[3], 1, 1) = "*", SubStr(fields[5], 1, 1) = "*")
    }

    ; Returns a Map of value -> true for one field.
    static _Field(text, lo, hi, label, names := "") {
        out := Map()
        for part in StrSplit(text, ",") {
            if (part = "")
                throw ValueError("cron " label " '" text "' has an empty list item.")
            step := 1
            if InStr(part, "/") {
                pieces := StrSplit(part, "/")
                if (pieces.Length != 2 || !RegExMatch(pieces[2], "^\d+$") || Integer(pieces[2]) < 1)
                    throw ValueError("cron " label " '" part "' needs a positive step after '/'.")
                step := Integer(pieces[2])
                part := pieces[1]
                stepped := true
            } else
                stepped := false
            if (part = "*") {
                first := lo, last := hi
            } else if InStr(part, "-") {
                bounds := StrSplit(part, "-")
                if (bounds.Length != 2)
                    throw ValueError("cron " label " '" part "' is not a valid range.")
                first := Cron._Value(bounds[1], lo, hi, label, names)
                last := Cron._Value(bounds[2], lo, hi, label, names)
                if (first > last)
                    throw ValueError("cron " label " range '" part "' runs backwards.")
            } else {
                first := Cron._Value(part, lo, hi, label, names)
                last := stepped ? hi : first
            }
            v := first
            while (v <= last) {
                out[v] := true
                v += step
            }
        }
        return out
    }

    static _Value(text, lo, hi, label, names) {
        if RegExMatch(text, "^\d+$") {
            v := Integer(text)
        } else if (names is Array) {
            v := ""
            for i, name in names {
                if (StrLower(text) = name) {
                    v := names = Cron.Days ? i - 1 : i
                    break
                }
            }
            if (v = "")
                throw ValueError("cron " label " '" text "' is not a number or name.")
        } else
            throw ValueError("cron " label " '" text "' is not a number.")
        if (v < lo || v > hi)
            throw ValueError("cron " label " " v " is outside " lo "-" hi ".")
        return v
    }

    _Has(field, value) => field.Has(value) && field[value]

    ; True when the minute of `stamp` (YYYYMMDDHHMISS) matches.
    Matches(stamp) {
        if !this._Has(this.minutes, Integer(SubStr(stamp, 11, 2)))
            return false
        if !this._Has(this.hours, Integer(SubStr(stamp, 9, 2)))
            return false
        return this._DayMatches(stamp)
    }

    _DayMatches(stamp) {
        if !this._Has(this.months, Integer(SubStr(stamp, 5, 2)))
            return false
        dayOk := this._Has(this.days, Integer(SubStr(stamp, 7, 2)))
        weekdayOk := this._Has(this.weekdays, Integer(FormatTime(stamp, "WDay")) - 1)
        if (!this.dayStar && !this.weekdayStar)
            return dayOk || weekdayOk
        return dayOk && weekdayOk
    }

    ; The last matching minute strictly before the minute of `stamp`, as
    ; YYYYMMDDHHMI00, or "" when none falls in the previous SearchYears years.
    Previous(stamp) {
        t := DateAdd(SubStr(stamp, 1, 12) "00", -1, "Minutes")
        limit := (Integer(SubStr(t, 1, 4)) - Cron.SearchYears) "0101000000"
        while (t >= limit) {
            if !this._DayMatches(t) {
                t := DateAdd(SubStr(t, 1, 8) "235900", -1, "Days")
                continue
            }
            if !this._Has(this.hours, Integer(SubStr(t, 9, 2))) {
                t := DateAdd(SubStr(t, 1, 10) "5900", -1, "Hours")
                continue
            }
            if !this._Has(this.minutes, Integer(SubStr(t, 11, 2))) {
                t := DateAdd(t, -1, "Minutes")
                continue
            }
            return t
        }
        return ""
    }

    ; The first matching minute strictly after `stamp`, as YYYYMMDDHHMI00, or
    ; "" when none falls in the next SearchYears years (e.g. "0 0 31 2 *").
    Next(stamp) {
        t := DateAdd(SubStr(stamp, 1, 12) "00", 1, "Minutes")
        limit := (Integer(SubStr(t, 1, 4)) + Cron.SearchYears) "0101000000"
        while (t < limit) {
            if !this._DayMatches(t) {
                t := DateAdd(SubStr(t, 1, 8) "000000", 1, "Days")
                continue
            }
            if !this._Has(this.hours, Integer(SubStr(t, 9, 2))) {
                t := DateAdd(SubStr(t, 1, 10) "0000", 1, "Hours")
                continue
            }
            if !this._Has(this.minutes, Integer(SubStr(t, 11, 2))) {
                t := DateAdd(t, 1, "Minutes")
                continue
            }
            return t
        }
        return ""
    }
}
