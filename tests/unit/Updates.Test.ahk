#Requires AutoHotkey v2.0

class Updates_Tests {
    static Toasts := []
    static GitCalls := []
    static Restarts := 0

    static Setup() {
        StatusLog.Path := A_Temp "\hotkit-updates-" A_TickCount ".log"
        Updates_Tests.Toasts := []
        Updates_Tests.GitCalls := []
        Updates_Tests.Restarts := 0
        Updates.Version := "1.4.2"
        Updates.RepoDir := "C:\hotkit"
        Updates.Settings := Updates.ReadSettings(Config.FromText("{}"))
        Updates.Available := ""
        Updates.Busy := false
        Updates._checking := false
        Updates._notified := ""
        Updates._autoFailed := ""
        Updates.Toaster := (options, lines*) => Updates_Tests.Toasts.Push(Updates_Tests.Join(lines))
        Updates.OnRestart := () => Updates_Tests.Restarts++
    }

    static Teardown() {
        if (Updates._autoTimer != "")
            SetTimer(Updates._autoTimer, 0)
        Updates._autoTimer := ""
        Updates.Toaster := ""
        Updates.GitRunner := ""
        Updates.Fetcher := ""
        Updates.OnRestart := ""
        Updates.Available := ""
        EnvSet("HOTKIT_UPDATED_FROM")
        try FileDelete(StatusLog.Path)
        StatusLog.Path := ""
    }

    static Join(lines) {
        out := ""
        for line in lines
            out .= (A_Index = 1 ? "" : " ") line
        return out
    }

    static Release(tag, extra := "") => '{ "tag_name": "' tag '", "html_url": "https://example.test/' tag '"' extra ' }'

    ; Answers every check with the given status and body.
    static Respond(status, text, error := "") {
        Updates.Fetcher := (url, done) => done.Call(status, text, error)
    }

    ; Fake git: answers maps a command prefix to { exit, out }; anything else
    ; succeeds with no output. The checkout's own root is reported by default.
    static FakeGit(answers := "") {
        answers := answers is Map ? answers : Map()
        if (!answers.Has("rev-parse"))
            answers["rev-parse"] := { exit: 0, out: "C:/hotkit" }
        Updates.GitRunner := (args) => Updates_Tests._Git(answers, args)
    }

    static _Git(answers, args) {
        Updates_Tests.GitCalls.Push(args)
        for prefix, result in answers {
            if (SubStr(args, 1, StrLen(prefix)) = prefix)
                return result
        }
        return { exit: 0, out: "" }
    }

    static Test_DefaultSettings() {
        s := Updates.ReadSettings(Config.FromText("{}"))
        Assert.True(s.check)
        Assert.Equal("manual", s.apply)
        Assert.Equal(6, s.intervalHours)
        Assert.Equal("mikejhill/hotkit", s.repository)
        Assert.Equal(0, s.problems.Length)
    }

    static Test_CustomSettings() {
        s := Updates.ReadSettings(Config.FromText('{ "settings": { "updates": { "check": false, "apply": "Auto", '
            '"intervalHours": 1.5, "repository": "someone/fork" } } }'))
        Assert.False(s.check)
        Assert.Equal("auto", s.apply)
        Assert.Equal(1.5, s.intervalHours)
        Assert.Equal("someone/fork", s.repository)
        Assert.Equal(0, s.problems.Length)
    }

    static Test_InvalidSettingsFallBackWithProblems() {
        s := Updates.ReadSettings(Config.FromText('{ "settings": { "updates": { "apply": "always", '
            '"intervalHours": 0, "repository": "not a repo" } } }'))
        Assert.Equal("manual", s.apply)
        Assert.Equal(6, s.intervalHours)
        Assert.Equal("mikejhill/hotkit", s.repository)
        Assert.Equal(3, s.problems.Length)
        Assert.Contains(s.problems[1], "settings.updates.apply")
        Assert.Contains(s.problems[2], "settings.updates.intervalHours")
        Assert.Contains(s.problems[3], "settings.updates.repository")
    }

    static Test_ConfigureAddsProblems() {
        problems := []
        Updates.Configure(Config.FromText('{ "settings": { "updates": { "apply": 3 } } }'), problems)
        Assert.Equal(1, problems.Length)
        Assert.Contains(problems[1], "settings.updates.apply")
    }

    static Test_ParseVersion() {
        Assert.Equal("1,2,3", Updates_Tests.Csv(Updates.ParseVersion("1.2.3")))
        Assert.Equal("10,0,12", Updates_Tests.Csv(Updates.ParseVersion("v10.0.12")))
        for bad in ["1.2", "1.2.3-rc.1", "v1.2.3.4", "", "latest"]
            Assert.Equal("", Updates.ParseVersion(bad), bad)
    }

    static Csv(list) {
        out := ""
        for v in list
            out .= (A_Index = 1 ? "" : ",") v
        return out
    }

    static Test_CompareIsNumericNotTextual() {
        Assert.Equal(1, Updates.Compare("1.10.0", "1.9.9"))
        Assert.Equal(-1, Updates.Compare("v1.9.9", "1.10.0"))
        Assert.Equal(0, Updates.Compare("v2.0.0", "2.0.0"))
        Assert.Equal(1, Updates.Compare("2.0.0", "1.99.99"))
        Assert.Throws(() => Updates.Compare("1.0", "1.0.0"), "Not a version")
    }

    static Test_ParseRelease() {
        r := Updates.ParseRelease(Updates_Tests.Release("v1.5.0"))
        Assert.Equal("1.5.0", r.version)
        Assert.Equal("v1.5.0", r.tag)
        Assert.Equal("https://example.test/v1.5.0", r.url)
        Assert.Equal("", Updates.ParseRelease(Updates_Tests.Release("v1.5.0", ', "prerelease": true')))
        Assert.Equal("", Updates.ParseRelease(Updates_Tests.Release("v1.5.0", ', "draft": true')))
        Assert.Equal("", Updates.ParseRelease(Updates_Tests.Release("nightly")))
        Assert.Throws(() => Updates.ParseRelease("[]"), "Unexpected response")
    }

    static Test_MenuTextAndStatus() {
        r := { version: "1.5.0" }
        Assert.Equal("Check for &Updates", Updates.MenuText("", false))
        Assert.Equal("&Update to v1.5.0", Updates.MenuText(r, false))
        Assert.Equal("Updating to v1.5.0…", Updates.MenuText(r, true))
        Assert.Equal("", Updates.Status(""))
        Assert.Equal("v1.5.0 available", Updates.Status(r))
    }

    static Test_CheckFindsNewerReleaseAndNotifiesOnce() {
        Updates_Tests.Respond(200, Updates_Tests.Release("v1.5.0"))
        Updates.Check()
        Assert.Equal("1.5.0", Updates.Available.version)
        Assert.Equal(1, Updates_Tests.Toasts.Length)
        Assert.Equal("hotkit 1.5.0 is available Tray › Update to v1.5.0", Updates_Tests.Toasts[1])
        Updates.Check()
        Assert.Equal(1, Updates_Tests.Toasts.Length, "a scheduled check repeats no toast")
        Updates.Check(true)
        Assert.Equal(2, Updates_Tests.Toasts.Length, "a manual check always answers")
        Assert.Equal(0, Updates_Tests.GitCalls.Length, "manual mode installs nothing by itself")
    }

    static Test_CheckUsesConfiguredRepository() {
        Updates.Settings := Updates.ReadSettings(Config.FromText('{ "settings": { "updates": { "repository": "a/b" } } }'))
        seen := []
        Updates.Fetcher := (url, done) => (seen.Push(url), done.Call(200, Updates_Tests.Release("v1.0.0"), ""))
        Updates.Check()
        Assert.Equal("https://api.github.com/repos/a/b/releases/latest", seen[1])
    }

    static Test_SameOrOlderReleaseIsNotOffered() {
        for tag in ["v1.4.2", "v1.4.1", "v0.9.0"] {
            Updates.Available := { version: "9.9.9" }
            Updates_Tests.Respond(200, Updates_Tests.Release(tag))
            Updates.Check()
            Assert.Equal("", Updates.Available, tag)
        }
        Assert.Equal(0, Updates_Tests.Toasts.Length, "scheduled checks stay quiet")
        Updates.Check(true)
        Assert.Equal("hotkit is up to date Version 1.4.2", Updates_Tests.Toasts[1])
    }

    static Test_FailedCheckIsQuietUnlessManual() {
        Updates_Tests.Respond(0, "", "The server name or address could not be resolved")
        Updates.Check()
        Assert.Equal(0, Updates_Tests.Toasts.Length)
        Assert.Contains(FileRead(StatusLog.Path, "UTF-8"), "[WARN] update check failed: The server name")
        Updates.Check(true)
        Assert.Equal("Couldn't check for updates: The server name or address could not be resolved", Updates_Tests.Toasts[1])
        Updates_Tests.Respond(404, "")
        Updates.Check(true)
        Assert.Equal("Couldn't check for updates: No releases found for mikejhill/hotkit.", Updates_Tests.Toasts[2])
        Updates_Tests.Respond(200, "not json")
        Updates.Check(true)
        Assert.Equal(3, Updates_Tests.Toasts.Length)
        Assert.Equal("", Updates.Available)
    }

    static Test_InstallFastForwardsToTagAndRestarts() {
        Updates.Available := { version: "1.5.0", tag: "v1.5.0", url: "" }
        Updates_Tests.FakeGit()
        Updates.Install()
        calls := Updates_Tests.GitCalls
        Assert.Equal(6, calls.Length)
        Assert.Equal("rev-parse --show-toplevel", calls[1])
        Assert.Equal("status --porcelain --untracked-files=no", calls[2])
        Assert.Equal("symbolic-ref -q HEAD", calls[3])
        Assert.Equal('fetch --no-tags "https://github.com/mikejhill/hotkit.git" "refs/tags/v1.5.0:refs/tags/v1.5.0"', calls[4])
        Assert.Equal('merge-base --is-ancestor HEAD "refs/tags/v1.5.0"', calls[5])
        Assert.Equal('merge --ff-only "refs/tags/v1.5.0"', calls[6])
        Assert.Equal(1, Updates_Tests.Restarts)
        Assert.Equal("1.4.2", EnvGet("HOTKIT_UPDATED_FROM"), "the new process is told what it replaced")
        Assert.Equal(0, Updates_Tests.Toasts.Length)
    }

    static Test_InstallRefusals() {
        cases := [
            [Map("rev-parse", { exit: 128, out: "fatal: not a git repository" }), "isn't running from its own git checkout", 1],
            [Map("rev-parse", { exit: 0, out: "C:/elsewhere" }), "isn't running from its own git checkout", 1],
            [Map("rev-parse", { exit: 9009, out: "'git' is not recognized" }), "Git isn't installed", 1],
            [Map("status", { exit: 0, out: " M src/Main.ahk" }), "uncommitted changes", 2],
            [Map("symbolic-ref", { exit: 1, out: "" }), "isn't on a branch", 3],
            [Map("fetch", { exit: 128, out: "remote: Not Found`nfatal: couldn't find remote ref" }),
                "Couldn't download v1.5.0: fatal: couldn't find remote ref", 4],
            [Map("merge-base", { exit: 1, out: "" }), "has commits that v1.5.0 doesn't have", 5],
            [Map("merge --ff-only", { exit: 128, out: "fatal: Not possible to fast-forward, aborting." }),
                "git merge failed: fatal: Not possible to fast-forward, aborting.", 6],
        ]
        for c in cases {
            Updates_Tests.GitCalls := []
            Updates_Tests.Toasts := []
            Updates.Available := { version: "1.5.0", tag: "v1.5.0", url: "" }
            Updates_Tests.FakeGit(c[1])
            Updates.Install(true)
            Assert.Equal(0, Updates_Tests.Restarts, c[2])
            Assert.Equal(c[3], Updates_Tests.GitCalls.Length, c[2] ": stops at the failing step")
            Assert.Equal(1, Updates_Tests.Toasts.Length, c[2])
            Assert.Contains(Updates_Tests.Toasts[1], "Couldn't update to v1.5.0: ")
            Assert.Contains(Updates_Tests.Toasts[1], c[2])
            Assert.False(Updates.Busy)
        }
        Assert.Equal("", EnvGet("HOTKIT_UPDATED_FROM"))
    }

    static Test_InstallWithoutKnownReleaseChecksFirst() {
        Updates_Tests.Respond(200, Updates_Tests.Release("v1.4.2"))
        Updates_Tests.FakeGit()
        Updates.Install()
        Assert.Equal(0, Updates_Tests.GitCalls.Length)
        Assert.Equal("hotkit is up to date Version 1.4.2", Updates_Tests.Toasts[1])
    }

    static Test_AutoModeWaitsForIdleThenInstalls() {
        Updates.Settings := Updates.ReadSettings(Config.FromText('{ "settings": { "updates": { "apply": "auto" } } }'))
        Updates_Tests.FakeGit()
        Updates_Tests.Respond(200, Updates_Tests.Release("v1.5.0"))
        saved := Updates.IdleMs
        try {
            Updates.IdleMs := 0x7FFFFFFF
            Updates.Check()
            Assert.Equal(0, Updates_Tests.GitCalls.Length, "not idle yet")
            Assert.Equal(0, Updates_Tests.Toasts.Length, "auto mode doesn't announce what it will install")
            Assert.True(Updates._autoTimer != "")
            Updates.IdleMs := 0
            Updates._AutoTick()
            Assert.Equal(1, Updates_Tests.Restarts)
            Assert.Equal("", Updates._autoTimer)
        } finally {
            Updates.IdleMs := saved
        }
    }

    static Test_AutoModeFailureFallsBackToManual() {
        Updates.Settings := Updates.ReadSettings(Config.FromText('{ "settings": { "updates": { "apply": "auto" } } }'))
        Updates_Tests.FakeGit(Map("status", { exit: 0, out: " M x" }))
        Updates_Tests.Respond(200, Updates_Tests.Release("v1.5.0"))
        saved := Updates.IdleMs
        try {
            Updates.IdleMs := 0
            Updates.Check()
            Assert.Contains(Updates_Tests.Toasts[1], "uncommitted changes")
            calls := Updates_Tests.GitCalls.Length
            Updates.Check()
            Assert.Equal(calls, Updates_Tests.GitCalls.Length, "no retry for a version that failed")
            Assert.Equal("1.5.0", Updates.Available.version, "still offered in the tray")
            Assert.Equal("hotkit 1.5.0 is available Tray › Update to v1.5.0", Updates_Tests.Toasts[2])
        } finally {
            Updates.IdleMs := saved
        }
    }

    static Test_LastLine() {
        Assert.Equal("b", Updates.LastLine("a`r`nb`r`n"))
        Assert.Equal("", Updates.LastLine(""))
    }
}
TestRunner.Add(Updates_Tests)
