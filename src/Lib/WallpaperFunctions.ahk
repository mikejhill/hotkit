#Requires AutoHotkey v2.0

#Include %A_LineFile%\..\Debugger.ahk


; ============================================================
; Wallpaper + Bing Wallpaper Utilities (AutoHotkey v2)
; Public API:
;   SetWallpaper(path, style := "Fill", monitorID := "")
;   SetBingWallpaper(cacheDir := "", maxAgeDays := 5, style := "Fill")
;     - Downloads today's Bing wallpaper (with resolution fallbacks),
;       caches it, prunes old files, and sets it as the wallpaper.
;     - Returns the cached file path used.
; ============================================================
class WallpaperFunctions {
    ; -------------------------
    ; Core: SetWallpaper
    ; -------------------------
    static SetWallpaper(path, style := "Fill", monitorID := "") {
        if (!FileExist(path)) {
            throw Error(Format("Image path '{}' does not exist.", path))
        }

        styles := Map(
            "Fill", { WallpaperStyle: "10", TileWallpaper: "0" },
            "Fit", { WallpaperStyle: "6", TileWallpaper: "0" },
            "Stretch", { WallpaperStyle: "2", TileWallpaper: "0" },
            "Tile", { WallpaperStyle: "0", TileWallpaper: "1" },
            "Center", { WallpaperStyle: "0", TileWallpaper: "0" },
            "Span", { WallpaperStyle: "22", TileWallpaper: "0" }
        )
        if (!styles.Has(style)) {
            throw Error("Invalid style. Use: Fill | Fit | Stretch | Tile | Center | Span")
        }

        settings := styles[style]
        regDesktop := "HKCU\Control Panel\Desktop"

        if (monitorID = "") {
            RegWrite settings.WallpaperStyle, "REG_SZ", regDesktop, "WallpaperStyle"
            RegWrite settings.TileWallpaper, "REG_SZ", regDesktop, "TileWallpaper"

            SPI_SETDESKWALLPAPER := 0x0014
            SPIF_UPDATEINIFILE := 0x01
            SPIF_SENDCHANGE := 0x02

            ok := DllCall("user32.dll\SystemParametersInfoW"
                , "UInt", SPI_SETDESKWALLPAPER
                , "UInt", 0
                , "Str", path
                , "UInt", SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
                , "Int")
            if (!ok) {
                throw Error(Format("SystemParametersInfoW failed (LastError={}).", A_LastError))
            }
            return true
        } else {
            subkey := regDesktop . "\PerMonitorSettings\" . monitorID
            if (!WallpaperFunctions.RegKeyExists(subkey)) {
                throw Error(Format("MonitorID '{}' not found under PerMonitorSettings.", monitorID))
            }

            cacheDir := A_AppData . "\Microsoft\Windows\Themes\CachedFiles"
            DirCreate(cacheDir)
            randHex := Format("{:08X}", Random(0, 0xFFFFFFFF))
            destPath := cacheDir . "\" . randHex . ".jpg"
            FileCopy(path, destPath, true)

            RegWrite destPath, "REG_SZ", subkey, "WallpaperPath"
            RegWrite settings.WallpaperStyle, "REG_SZ", regDesktop, "WallpaperStyle"
            RegWrite settings.TileWallpaper, "REG_SZ", regDesktop, "TileWallpaper"

            WallpaperFunctions.RefreshDesktop()
            return true
        }
    }

    ; -------------------------
    ; Public: SetBingWallpaper
    ; -------------------------
    static SetBingWallpaper(cacheDir := "", maxAgeDays := 5, style := "Fill") {
        if (cacheDir = "")
            cacheDir := EnvGet("LocalAppData") . "\BingWallpapers"
        WallpaperFunctions.EnsureDirectory(cacheDir)
        WallpaperFunctions.PruneOldFiles(cacheDir, maxAgeDays)

        todayStamp := FormatTime(, "yyyyMMdd")

        ; Try to fetch and set Bing wallpaper; fail gracefully if network unavailable
        try {
            ; Query Bing API (once) to get urlbase and a stable key
            api := "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US"
            apiText := WallpaperFunctions.HttpGetText(api, 5000)
            urlBase := WallpaperFunctions.ExtractUrlBase(apiText)
            if (urlBase = "") {
                throw Error("Bing API did not return urlbase.")
            }
            imageKey := WallpaperFunctions.GetImageKeyFromUrlBase(urlBase)

            ; Find the first reachable image URL using resolution fallbacks
            imgInfo := WallpaperFunctions.GetBingImageUrl(urlBase)
            imgUrl := imgInfo.Url
            resSfx := imgInfo.ResSuffix

            fileName := todayStamp . "_" . imageKey . resSfx . ".jpg"  ; e.g., 20250902_OHR.FloatingTorii_UHD.jpg
            cachedFile := cacheDir . "\" . fileName

            if (!FileExist(cachedFile)) {
                Download(imgUrl, cachedFile)
                ; touch time to now in case server preserved old time
                FileSetTime(, cachedFile, "M")
            }

            WallpaperFunctions.SetWallpaper(cachedFile, style)
            return cachedFile
        } catch as err {
            ; Network error or Bing API failure - try to use most recent cached wallpaper
            Debugger.Log("Failed to fetch Bing wallpaper: " . err.Message, "WARN")

            cachedFile := WallpaperFunctions._GetMostRecentCachedWallpaper(cacheDir)
            if (cachedFile != "") {
                Debugger.Log("Using cached wallpaper: " . cachedFile, "INFO")
                WallpaperFunctions.SetWallpaper(cachedFile, style)
                return cachedFile
            } else {
                Debugger.Log("No cached wallpaper available. Skipping wallpaper change.", "WARN")
                return ""
            }
        }
    }

    ; -------------------------
    ; Helpers (filesystem)
    ; -------------------------
    static EnsureDirectory(path) {
        if (!DirExist(path)) {
            DirCreate(path)
        }
    }

    static _GetMostRecentCachedWallpaper(cacheDir) {
        if (!DirExist(cacheDir)) {
            return ""
        }

        mostRecent := ""
        mostRecentTime := ""

        loop files, cacheDir . "\*.jpg", "F" {
            modTime := FileGetTime(A_LoopFileFullPath, "M")
            if (mostRecentTime = "" || DateDiff(modTime, mostRecentTime, "Seconds") > 0) {
                mostRecentTime := modTime
                mostRecent := A_LoopFileFullPath
            }
        }

        return mostRecent
    }

    static PruneOldFiles(path, maxAgeDays) {
        loop files, path . "\*", "F" {
            modTime := FileGetTime(A_LoopFileFullPath, "M")  ; yyyymmddHH24MISS
            if (DateDiff(modTime, A_Now, "Days") > maxAgeDays) {
                try {
                    FileDelete(A_LoopFileFullPath)
                } catch {
                    ; ignore failures
                }
            }
        }
    }

    ; -------------------------
    ; Helpers (registry/refresh)
    ; -------------------------
    static RegKeyExists(key) {
        try {
            RegRead(key)  ; default value
            return true
        } catch {
            try {
                RegRead(key, "WallpaperPath")
                return true
            } catch {
                return false
            }
        }
    }

    static RefreshDesktop() {
        SPI_SETDESKWALLPAPER := 0x0014
        SPIF_UPDATEINIFILE := 0x01
        SPIF_SENDCHANGE := 0x02
        DllCall("user32.dll\SystemParametersInfoW"
            , "UInt", SPI_SETDESKWALLPAPER
            , "UInt", 0
            , "Ptr", 0
            , "UInt", SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
            , "Int")
    }

    ; -------------------------
    ; Helpers (HTTP + Bing)
    ; -------------------------
    static HttpGetText(url, timeoutMs := 5000) {
        try {
            req := ComObject("WinHttp.WinHttpRequest.5.1")
            ; timeouts: resolve, connect, send, receive
            req.SetTimeouts(timeoutMs, timeoutMs, timeoutMs, timeoutMs)
            req.Open("GET", url, false)
            req.Send()
            if (req.Status != 200) {
                throw Error(Format("HTTP GET failed {} {}", req.Status, req.StatusText))
            }
            return req.ResponseText
        } catch as err {
            ; Re-throw with more context about network failure
            throw Error(Format("Network request failed for {}: {}", url, err.Message), -1, err)
        }
    }

    static HttpHeadOk(url, timeoutMs := 5000) {
        try {
            req := ComObject("WinHttp.WinHttpRequest.5.1")
            req.SetTimeouts(timeoutMs, timeoutMs, timeoutMs, timeoutMs)
            req.Open("HEAD", url, false)
            req.Send()
            return (req.Status >= 200 && req.Status < 300)
        } catch {
            return false
        }
    }

    static ExtractUrlBase(jsonText) {
        ; Match "urlbase":"..."; keep raw (Bing returns paths like /th?id=OHR.FloatingTorii)
        m := 0
        if (RegExMatch(jsonText, "`"urlbase`"\s*:\s*`"([^`"]+)`"", &m)) {
            return m[1]
        }
        return ""
    }

    static GetBingImageUrl(urlBase) {
        base := "https://www.bing.com"
        res := ["_UHD", "_1920x1200", "_1920x1080", "_1366x768", "_1280x720", "_1024x768"]
        for r in res {
            cand := base . urlBase . r . ".jpg"
            if (WallpaperFunctions.HttpHeadOk(cand, 5000)) {
                return { Url: cand, ResSuffix: r }
            }
        }
        throw Error("Failed to find an available wallpaper resolution.")
    }

    static GetImageKeyFromUrlBase(urlBase) {
        m := 0
        if (RegExMatch(urlBase, "i)id=([^_&]+)", &m)) {
            return m[1]
        }
        ; fallback to leaf
        ; urlBase examples: "/th?id=OHR.FloatingTorii" or "/th?id=OHR.FloatingTorii_EN-US"
        SplitPath(urlBase, &leaf)
        return (leaf != "") ? leaf : "BingImage"
    }
}
