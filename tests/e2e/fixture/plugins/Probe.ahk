#Requires AutoHotkey v2.0

; Test-only plugin: records action calls to a file the e2e driver reads.
App.AddPlugin("probe", (settings) => ProbePlugin.Init(settings))

class ProbePlugin {
    static File := ""

    static Init(settings) {
        ProbePlugin.File := MapGet(settings, "file", A_Temp "\hotkit-probe.txt")
        ActionRegistry.Register("probe.mark", (name) => ProbePlugin.Mark(name), { module: "plugin:probe", description: "Record a mark" })
        App.OnReady(() => (ProbePlugin.Mark("pid:" ProcessExist()), ProbePlugin.Mark("icon:" A_IconFile), ProbePlugin.Mark("iconHidden:" A_IconHidden), ProbePlugin.Mark("ready")))
    }

    ; The e2e driver reads this file while marks are written: open it sharing
    ; all access, and retry briefly if the driver holds it at that moment.
    static Mark(name) {
        loop 50 {
            try {
                f := FileOpen(ProbePlugin.File, "a", "UTF-8-RAW")
                f.Write(name "`n")
                f.Close()
                return
            } catch OSError as e {
                if (A_Index = 50)
                    throw e
                Sleep(20)
            }
        }
    }
}
