#Requires AutoHotkey v2.0

class Cron_Tests {
    static Test_MatchesExactMinute() {
        c := Cron.Parse("30 7 * * *")
        Assert.True(c.Matches("20261127073000"))
        Assert.True(c.Matches("20261127073059"), "seconds are ignored")
        Assert.False(c.Matches("20261127073100"))
        Assert.False(c.Matches("20261127083000"))
    }

    static Test_WeekdayNamesAndRanges() {
        c := Cron.Parse("0 9 * * mon-fri")
        Assert.True(c.Matches("20261127090000"), "Friday")
        Assert.False(c.Matches("20261128090000"), "Saturday")
        Assert.False(c.Matches("20261129090000"), "Sunday")
        Assert.True(c.Matches("20261130090000"), "Monday")
    }

    static Test_SundayIsZeroOrSeven() {
        Assert.True(Cron.Parse("0 0 * * 0").Matches("20261129000000"))
        Assert.True(Cron.Parse("0 0 * * 7").Matches("20261129000000"))
        Assert.True(Cron.Parse("0 0 * * SUN").Matches("20261129000000"), "names ignore case")
    }

    static Test_StepsAndLists() {
        c := Cron.Parse("*/15 8-18/2 * * *")
        Assert.True(c.Matches("20261127084500"))
        Assert.True(c.Matches("20261127180000"))
        Assert.False(c.Matches("20261127090000"), "odd hour")
        Assert.False(c.Matches("20261127081000"))
        l := Cron.Parse("5,10,50 * * * *")
        Assert.True(l.Matches("20261127121000"))
        Assert.False(l.Matches("20261127121100"))
    }

    static Test_StartWithStepRunsToMaximum() {
        c := Cron.Parse("50/5 * * * *")
        Assert.True(c.Matches("20261127125500"))
        Assert.False(c.Matches("20261127120000"))
        Assert.False(c.Matches("20261127124500"))
    }

    static Test_MonthNames() {
        c := Cron.Parse("0 0 1 jan,Jul *")
        Assert.True(c.Matches("20270701000000"))
        Assert.False(c.Matches("20270801000000"))
    }

    static Test_BothDayFieldsRestrictedMatchEither() {
        c := Cron.Parse("0 12 1 * fri")
        Assert.True(c.Matches("20261127120000"), "a Friday that isn't the 1st")
        Assert.True(c.Matches("20261201120000"), "the 1st, a Tuesday")
        Assert.False(c.Matches("20261130120000"), "Monday the 30th")
    }

    static Test_OneDayFieldRestrictedMatchesBoth() {
        c := Cron.Parse("0 12 */2 * fri")
        Assert.True(c.Matches("20261127120000"), "Friday the 27th")
        Assert.False(c.Matches("20261120120000"), "Friday the 20th: day is a star field, so both must match")
    }

    static Test_Macros() {
        Assert.True(Cron.Parse("@daily").Matches("20261127000000"))
        Assert.False(Cron.Parse("@daily").Matches("20261127000100"))
        Assert.True(Cron.Parse("@HOURLY").Matches("20261127130000"))
        Assert.True(Cron.Parse("@weekly").Matches("20261129000000"))
        Assert.True(Cron.Parse("@monthly").Matches("20261201000000"))
        Assert.True(Cron.Parse("@yearly").Matches("20270101000000"))
        Assert.Equal("@daily", Cron.Parse(" @daily ").text)
    }

    static Test_NextFindsFollowingMinute() {
        c := Cron.Parse("30 7 * * *")
        Assert.Equal("20261127073000", c.Next("20261127000000"))
        Assert.Equal("20261128073000", c.Next("20261127073000"), "strictly after")
        Assert.Equal("20261128073000", c.Next("20261127073045"))
    }

    static Test_NextCrossesMonthAndYear() {
        Assert.Equal("20270101000000", Cron.Parse("@yearly").Next("20261127120000"))
        Assert.Equal("20261201000000", Cron.Parse("0 0 1 * *").Next("20261127120000"))
        Assert.Equal("20261130090000", Cron.Parse("0 9 * * mon").Next("20261127120000"))
    }

    static Test_PreviousFindsLastMatchBefore() {
        c := Cron.Parse("30 7 * * *")
        Assert.Equal("20261127073000", c.Previous("20261127073100"))
        Assert.Equal("20261126073000", c.Previous("20261127073000"), "strictly before")
        Assert.Equal("20261126073000", c.Previous("20261127073059"), "seconds are ignored")
        Assert.Equal("20261130090000", Cron.Parse("0 9 * * mon").Previous("20261203000000"))
        Assert.Equal("20261231235800", Cron.Parse("0-58 * * * *").Previous("20270101000000"), "crosses a year")
        Assert.Equal("20240229000000", Cron.Parse("0 0 29 2 *").Previous("20261127000000"))
        Assert.Equal("", Cron.Parse("0 0 31 2 *").Previous("20261127000000"))
    }

    static Test_NextFindsLeapDay() {
        Assert.Equal("20280229000000", Cron.Parse("0 0 29 2 *").Next("20261127000000"))
    }

    static Test_NextEmptyWhenNeverMatches() {
        Assert.Equal("", Cron.Parse("0 0 31 2 *").Next("20261127000000"))
        Assert.Equal("", Cron.Parse("0 0 30 feb *").Next("20261127000000"))
    }

    static Test_RejectsBadExpressions() {
        Assert.Throws(() => Cron.Parse(""), "5 fields")
        Assert.Throws(() => Cron.Parse("* * * *"), "got 4")
        Assert.Throws(() => Cron.Parse("60 * * * *"), "minute 60 is outside 0-59")
        Assert.Throws(() => Cron.Parse("* 24 * * *"), "hour")
        Assert.Throws(() => Cron.Parse("* * 0 * *"), "day of month")
        Assert.Throws(() => Cron.Parse("* * * 13 *"), "month")
        Assert.Throws(() => Cron.Parse("* * * * 8"), "day of week")
        Assert.Throws(() => Cron.Parse("*/0 * * * *"), "positive step")
        Assert.Throws(() => Cron.Parse("5-1 * * * *"), "backwards")
        Assert.Throws(() => Cron.Parse("1,,2 * * * *"), "empty list item")
        Assert.Throws(() => Cron.Parse("* * * foo *"), "not a number or name")
        Assert.Throws(() => Cron.Parse("mon * * * *"), "not a number")
        Assert.Throws(() => Cron.Parse(5), "must be a string")
    }
}

TestRunner.Add(Cron_Tests)
