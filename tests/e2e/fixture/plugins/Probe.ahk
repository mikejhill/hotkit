#Requires AutoHotkey v2.0

; Test-only plugin: records action calls to a file the e2e driver reads.
App.AddPlugin("probe", (settings) => ProbePlugin.Init(settings))

class ProbePlugin {
    static File := ""

    static Init(settings) {
        ProbePlugin.File := MapGet(settings, "file", A_Temp "\hotkit-probe.txt")
        ActionRegistry.Register("probe.mark", (name) => ProbePlugin.Mark(name), { module: "plugin:probe", description: "Record a mark" })
        App.OnReady(() => (ProbePlugin.Mark("pid:" ProcessExist()), ProbePlugin.Mark("ready")))
    }

    static Mark(name) => FileAppend(name "`n", ProbePlugin.File, "UTF-8-RAW")
}
