#Requires AutoHotkey v2.0

; Looks for a newer hotkit release on GitHub and installs it into the git
; checkout hotkit runs from. Config:
;
;   "settings": {
;     "updates": {
;       "check": true,                    ; look for new releases (default true)
;       "apply": "manual",                ; "manual": tray › Update to vX.Y.Z
;                                         ; "auto": install and reload once you're idle
;       "intervalHours": 6,               ; how often to look (default 6, at most 720)
;       "repository": "mikejhill/hotkit"  ; GitHub owner/name to follow
;     }
;   }
;
; Installing fetches the release tag and fast-forwards the checkout to it. It
; refuses when the checkout has uncommitted changes, is not on a branch, or has
; commits the release doesn't have. hotkit then restarts itself.
class Updates {
    static DefaultRepository := "mikejhill/hotkit"
    static Version := ""            ; running version (set by App)
    static RepoDir := ""            ; checkout to update (set by App)
    static OnRestart := ""          ; fn() that restarts hotkit (set by App)
    static Settings := ""
    static Available := ""          ; { version, tag, url } of a newer release, or ""
    static Busy := false
    static FirstCheckMs := 60000
    static IdleMs := 120000
    static Fetcher := ""            ; tests: (url, done) => done(status, text, error)
    static GitRunner := ""          ; tests: (args) => { exit, out }
    static Toaster := ""            ; tests: (options, lines*) => ...
    static _checking := false
    static _notified := ""
    static _autoFailed := ""
    static _autoTimer := ""
    static _restartTimer := () => Updates._RestartWhenIdle()
    static _menu := ""
    static _menuItem := ""

    ; Reads settings.updates. Returns { check, apply, intervalHours,
    ; repository, problems }; invalid values fall back to their defaults.
    static ReadSettings(cfg) {
        s := cfg.Section("settings.updates")
        out := { check: !!MapGet(s, "check", true), apply: "manual", intervalHours: 6,
            repository: Updates.DefaultRepository, problems: [] }
        apply := MapGet(s, "apply", "manual")
        if (!IsObject(apply) && (apply = "manual" || apply = "auto"))
            out.apply := StrLower(apply)
        else
            out.problems.Push('settings.updates.apply: use "manual" or "auto"; using "manual".')
        hours := MapGet(s, "intervalHours", 6)
        if (IsNumber(hours) && hours >= 1 && hours <= 720)
            out.intervalHours := hours
        else
            out.problems.Push("settings.updates.intervalHours: use a number of hours from 1 to 720; using 6.")
        repo := MapGet(s, "repository", Updates.DefaultRepository)
        if (!IsObject(repo) && RegExMatch(repo, "^[\w.-]+/[\w.-]+$"))
            out.repository := repo
        else
            out.problems.Push('settings.updates.repository: use "owner/name"; using "' Updates.DefaultRepository '".')
        return out
    }

    ; Pure: [major, minor, patch] from "1.2.3" or "v1.2.3", or "" for anything
    ; else (including pre-release versions).
    static ParseVersion(text) {
        if (IsObject(text) || !RegExMatch(text, "^v?(\d+)\.(\d+)\.(\d+)$", &m))
            return ""
        return [Integer(m[1]), Integer(m[2]), Integer(m[3])]
    }

    ; Pure: -1, 0 or 1 as version a is older than, equal to or newer than b.
    static Compare(a, b) {
        pa := Updates.ParseVersion(a), pb := Updates.ParseVersion(b)
        if (pa = "" || pb = "")
            throw ValueError("Not a version: " (pa = "" ? a : b))
        loop 3 {
            if (pa[A_Index] != pb[A_Index])
                return pa[A_Index] > pb[A_Index] ? 1 : -1
        }
        return 0
    }

    ; Pure: { version, tag, url } from a GitHub "latest release" response, or
    ; "" for a draft, pre-release or tag that isn't vX.Y.Z.
    static ParseRelease(text) {
        data := Config.Normalize(JSON.Parse(text))
        if !(data is Map)
            throw ValueError("Unexpected response from GitHub.")
        tag := MapGet(data, "tag_name", "")
        if (MapGet(data, "draft", false) || MapGet(data, "prerelease", false) || Updates.ParseVersion(tag) = "")
            return ""
        return { version: LTrim(tag, "v"), tag: tag, url: MapGet(data, "html_url", "") }
    }

    ; Pure: the tray item's text.
    static MenuText(available, busy) {
        if (available = "")
            return "Check for &Updates"
        return busy ? "Updating to v" available.version "…" : "&Update to v" available.version
    }

    ; Pure: tray tooltip status.
    static Status(available) => available = "" ? "" : "v" available.version " available"

    ; ---------------- Running app                    ------------------------------

    static Configure(cfg, problems) {
        Updates.Settings := Updates.ReadSettings(cfg)
        for p in Updates.Settings.problems
            problems.Push(p)
    }

    ; Adds the tray item before the item named `before` and starts checking.
    static Start(trayMenu, before) {
        Updates._menu := trayMenu
        Updates._menuItem := Updates.MenuText("", false)
        try trayMenu.Insert(before, Updates._menuItem, (*) => Updates.Install())
        from := EnvGet("HOTKIT_UPDATED_FROM")
        if (from != "") {
            EnvSet("HOTKIT_UPDATED_FROM")
            Updates._Toast({ fadeDelay: 5000 }, "Updated hotkit to " Updates.Version, "From " from)
            StatusLog.Info("updated from " from " to " Updates.Version)
        }
        if (Updates.Settings.check) {
            SetTimer(() => Updates.Check(), -Updates.FirstCheckMs)
            SetTimer(() => Updates.Check(), Round(Updates.Settings.intervalHours * 3600000))
        }
    }

    ; Asks GitHub for the latest release. manual: report the result in a toast
    ; even when there is nothing new or the check fails.
    static Check(manual := false) {
        if (Updates._checking || Updates.Busy)
            return
        Updates._checking := true
        url := "https://api.github.com/repos/" Updates.Settings.repository "/releases/latest"
        fetch := Updates.Fetcher != "" ? Updates.Fetcher : ObjBindMethod(Updates, "HttpGet")
        fetch.Call(url, (status, text, error) => Updates._OnChecked(status, text, error, manual))
    }

    static _OnChecked(status, text, error, manual) {
        Updates._checking := false
        release := ""
        if (error = "" && status != 200)
            error := status = 404 ? "No releases found for " Updates.Settings.repository "." : "GitHub answered " status "."
        if (error = "") {
            try {
                release := Updates.ParseRelease(text)
            } catch as e {
                error := e.Message
            }
        }
        if (error != "") {
            StatusLog.Warn("update check failed: " error)
            if (manual)
                Updates._Toast({ color: "FF6060", fadeDelay: 5000 }, "Couldn't check for updates:", error)
            return
        }
        if (release = "" || Updates.Compare(release.version, Updates.Version) <= 0) {
            Updates._SetAvailable("")
            if (manual)
                Updates._Toast({ fadeDelay: 3000 }, "hotkit is up to date", "Version " Updates.Version)
            return
        }
        isNew := Updates.Available = "" || Updates.Available.version != release.version
        Updates._SetAvailable(release)
        if (isNew)
            StatusLog.Info("update available: " release.version)
        if (Updates.Settings.apply = "auto" && Updates._autoFailed != release.version) {
            Updates._StartAutoInstall()
            return
        }
        if (manual || Updates._notified != release.version) {
            Updates._notified := release.version
            Updates._Toast({ fadeDelay: 6000 }, "hotkit " release.version " is available",
                "Tray › Update to v" release.version)
        }
    }

    static _SetAvailable(release) {
        Updates.Available := release
        Updates._RefreshMenu()
        Tray.RefreshTip()
    }

    ; Auto mode installs only after IdleMs without keyboard or mouse input, so
    ; the restart doesn't interrupt typing.
    static _StartAutoInstall() {
        if (Updates._autoTimer != "")
            return
        Updates._autoTimer := () => Updates._AutoTick()
        SetTimer(Updates._autoTimer, 30000)
        Updates._AutoTick()
    }

    static _AutoTick() {
        if (A_TimeIdle < Updates.IdleMs || Updates.Busy)
            return
        SetTimer(Updates._autoTimer, 0)
        Updates._autoTimer := ""
        Updates.Install(true)
    }

    static _RestartWhenIdle() {
        if (A_TimeIdle < Updates.IdleMs) {
            SetTimer(Updates._restartTimer, -15000)
            return
        }
        if (Updates.OnRestart != "")
            Updates.OnRestart.Call()
    }

    ; The tray item and app.update: installs the available release, or checks
    ; for one when none is known yet.
    static Install(auto := false) {
        release := Updates.Available
        if (release = "") {
            if (!auto)
                Updates.Check(true)
            return
        }
        if (Updates.Busy)
            return
        Updates.Busy := true
        Updates._RefreshMenu()
        StatusLog.Info("updating to " release.version)
        result := Updates.Apply(release)
        Updates.Busy := false
        if (result.ok) {
            StatusLog.Info("updated to " release.version ", restarting")
            EnvSet("HOTKIT_UPDATED_FROM", Updates.Version)
            if (auto)
                Updates._RestartWhenIdle()  ; input may have resumed during the download
            else if (Updates.OnRestart != "")
                Updates.OnRestart.Call()
            return
        }
        Updates._RefreshMenu()
        StatusLog.Warn("update to " release.version " failed: " result.message)
        if (auto)
            Updates._autoFailed := release.version
        Updates._Toast({ color: "FF6060", fadeDelay: 8000 }, "Couldn't update to v" release.version ":", result.message)
        if (!auto && result.notGit && release.url != "")
            try Run(release.url)
    }

    ; Fast-forwards the checkout to the release tag. Returns { ok, message,
    ; notGit }; nothing is changed unless every check passes.
    static Apply(release) {
        fail := (message, notGit := false) => { ok: false, message: message, notGit: notGit }
        r := Updates.Git("rev-parse --show-toplevel")
        if (r.exit = 9009)
            return fail("Git isn't installed or isn't on PATH.", true)
        problem := Updates.CheckoutProblem(r, Updates.RepoDir)
        if (problem != "")
            return fail(problem.message, problem.notGit)
        r := Updates.Git("status --porcelain --untracked-files=no")
        if (r.exit != 0)
            return fail("git status failed: " Updates.Detail(r))
        if (r.out != "")
            return fail("The hotkit folder has uncommitted changes.")
        r := Updates.Git("symbolic-ref -q HEAD")
        if (r.exit != 0)
            return fail("The hotkit folder isn't on a branch.")
        headRef := Updates.LastLine(r.out)
        tag := release.tag
        ref := '"refs/tags/' tag '"'
        r := Updates.Git('fetch --no-tags "https://github.com/' Updates.Settings.repository '.git" "refs/tags/' tag ':refs/tags/' tag '"')
        if (r.exit != 0)
            return fail("Couldn't download " tag ": " Updates.Detail(r))
        if (Updates.Git("merge-base --is-ancestor HEAD " ref).exit != 0) {
            ; Case-sensitive: git ref names are, and "Main" isn't main.
            return fail(Updates.NotFastForwardMessage(headRef, tag))
        }
        r := Updates.Git("merge --ff-only " ref)
        if (r.exit != 0)
            return fail("git merge failed: " Updates.Detail(r))
        return { ok: true, message: "", notGit: false }
    }

    ; Why `git rev-parse --show-toplevel` (result r) doesn't confirm that
    ; repoDir is its own checkout: { message, notGit }, or "" when it does.
    ; Git may report a junction, subst drive, or short name by its real path.
    static CheckoutProblem(r, repoDir) {
        mismatch := (root, extra := "") => { notGit: true, message: "hotkit runs from " repoDir
            ", but git says that folder belongs to the checkout at " root extra "." }
        if (r.exit != 0) {
            text := (r.HasProp("err") ? r.err "`n" : "") r.out
            if (RegExMatch(text, "dubious ownership in repository at '([^'\r\n]+)'", &m)) {
                if (!Updates.SamePath(m[1], repoDir))
                    return mismatch(m[1], ", which another Windows account owns")
                ; PowerShell single quotes keep spaces and $ literal; ' doubles.
                return { notGit: false, message: "Git won't use the hotkit folder because another Windows account owns it "
                    "(often a clone made from an elevated prompt). To trust it, run in PowerShell: "
                    "git config --global --add safe.directory '" StrReplace(m[1], "'", "''") "'" }
            }
            detail := Updates.Detail(r)
            return { notGit: true, message: "Git can't use the hotkit folder " repoDir
                (detail != "" ? ": " detail : " (exit code " r.exit ").") }
        }
        root := Updates.LastLine(r.out)
        return Updates.SamePath(root, repoDir) ? "" : mismatch(root)
    }

    ; Whether two paths name the same folder, after resolving aliases.
    static SamePath(a, b) => a != "" && Paths.Normalize(Paths.RealPath(a)) = Paths.Normalize(Paths.RealPath(b))

    ; Pure: what went wrong in a git result: the last line of stderr, else of stdout.
    static Detail(r) {
        err := r.HasProp("err") ? Updates.LastLine(r.err) : ""
        return err != "" ? err : Updates.LastLine(r.out)
    }

    ; Why HEAD can't fast-forward to the release, and what to do about it.
    ; Typical cause: a feature branch left checked out, often a squash-merged
    ; one whose commits never appear in the release history.
    static NotFastForwardMessage(headRef, tag) {
        ref := '"refs/tags/' tag '"'
        ; Case-sensitive: git ref names are, and "Main" isn't main.
        if (SubStr(headRef, 1, 11) == "refs/heads/" && headRef !== "refs/heads/main") {
            branch := SubStr(headRef, 12)
            if (Updates.Git("merge-base --is-ancestor refs/heads/main " ref).exit = 0)
                return "hotkit is on the " branch " branch. Switch to main to update; " branch " keeps its commits."
            return "hotkit is on the " branch " branch, which has commits that " tag " doesn't have. Rebase them onto " tag " to update."
        }
        if (Updates.Git("merge-base --is-ancestor " ref " HEAD").exit = 0)
            return "hotkit's branch already has everything in " tag ", plus newer commits."
        return "hotkit's branch has commits that " tag " doesn't have. Rebase them onto " tag " to update."
    }

    ; Pure: last non-empty line of command output.
    static LastLine(text) {
        lines := StrSplit(Trim(text, " `t`r`n"), "`n", "`r")
        return lines.Length ? Trim(lines[lines.Length]) : ""
    }

    ; Runs git in the checkout without a window; returns { exit, out, err }
    ; with stdout and stderr apart, so warnings never read as command output.
    static Git(args) {
        if (Updates.GitRunner != "")
            return Updates.GitRunner.Call(args)
        base := A_Temp "\hotkit-git-" ProcessExist() "-" A_TickCount
        outFile := base ".out.txt", errFile := base ".err.txt"
        cmd := A_ComSpec ' /c set "GIT_TERMINAL_PROMPT=0" && git -C "' Updates.RepoDir '" ' args
            . ' > "' outFile '" 2> "' errFile '"'
        try {
            code := RunWait(cmd, Updates.RepoDir, "Hide")
        } catch as e {
            return { exit: -1, out: "", err: e.Message }
        }
        out := "", err := ""
        try out := FileRead(outFile, "UTF-8")
        try err := FileRead(errFile, "UTF-8")
        try FileDelete(outFile)
        try FileDelete(errFile)
        return { exit: code, out: Trim(out, " `t`r`n"), err: Trim(err, " `t`r`n") }
    }

    ; GETs url without blocking; calls done(status, text, error) once.
    static HttpGet(url, done) {
        try {
            req := ComObject("WinHttp.WinHttpRequest.5.1")
            req.Open("GET", url, true)
            req.SetRequestHeader("User-Agent", "hotkit/" Updates.Version)
            req.SetRequestHeader("Accept", "application/vnd.github+json")
            req.Send()
        } catch as e {
            return done.Call(0, "", Updates._ComMessage(e))
        }
        start := A_TickCount
        Poll() {
            try {
                finished := req.WaitForResponse(0)
            } catch as e {
                SetTimer(Poll, 0)
                return done.Call(0, "", Updates._ComMessage(e))
            }
            if (finished) {
                SetTimer(Poll, 0)
                status := 0, text := ""
                try {
                    status := req.Status
                    text := req.ResponseText
                }
                return done.Call(status, text, "")
            }
            if (A_TickCount - start > 30000) {
                SetTimer(Poll, 0)
                try req.Abort()
                return done.Call(0, "", "GitHub didn't answer within 30 seconds.")
            }
        }
        SetTimer(Poll, 250)
    }

    static _Toast(options, lines*) {
        if (Updates.Toaster != "")
            return Updates.Toaster.Call(options, lines*)
        Toast.ShowToast(options, lines*)
    }

    static _ComMessage(e) => Trim(RegExReplace(e.Message, "^\(0x[0-9A-Fa-f]+\)\s*"), " `t`r`n")

    static _RefreshMenu() {
        if (Updates._menu = "")
            return
        text := Updates.MenuText(Updates.Available, Updates.Busy)
        try {
            if (text != Updates._menuItem) {
                Updates._menu.Rename(Updates._menuItem, text)
                Updates._menuItem := text
            }
            if (Updates.Busy)
                Updates._menu.Disable(text)
            else
                Updates._menu.Enable(text)
        }
    }
}
