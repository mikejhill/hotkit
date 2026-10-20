#Requires AutoHotkey v2.0

class StatusLog_Tests {
    static Setup() {
        StatusLog.Path := A_Temp "\hotkit-statuslog-" A_TickCount ".log"
    }

    static Teardown() {
        try FileDelete(StatusLog.Path)
        StatusLog.Path := ""
        StatusLog.MaxBytes := 65536
        StatusLog.KeepLines := 300
    }

    static Test_WritesLevelAndFlattensNewlines() {
        StatusLog.Start("C:\cfg\config.json")
        StatusLog.Error("bad`nthing")
        lines := StrSplit(RTrim(FileRead(StatusLog.Path, "UTF-8"), "`n"), "`n")
        Assert.Equal(2, lines.Length)
        Assert.True(InStr(lines[1], "[INFO] started pid=") && InStr(lines[1], "config=C:\cfg\config.json"), lines[1])
        Assert.True(InStr(lines[2], "[ERROR] bad | thing"), lines[2])
    }

    static Test_TrimKeepsNewestLines() {
        StatusLog.MaxBytes := 100
        StatusLog.KeepLines := 3
        loop 20
            StatusLog.Info("line " A_Index)
        StatusLog.Trim()
        lines := StrSplit(RTrim(FileRead(StatusLog.Path, "UTF-8"), "`n"), "`n")
        Assert.Equal(3, lines.Length)
        Assert.True(InStr(lines[3], "line 20"), lines[3])
        Assert.True(InStr(lines[1], "line 18"), lines[1])
    }

    static Test_TrimLeavesSmallFileAlone() {
        StatusLog.Info("one")
        StatusLog.Trim()
        Assert.True(InStr(FileRead(StatusLog.Path, "UTF-8"), "[INFO] one"))
    }
}

TestRunner.Add(StatusLog_Tests)
