#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\QuickNote\NoteFormat.ahk

; Example plugin: appends a timestamped line to a text file.
;
;   "plugins": { "quickNote": { "file": "~\\Documents\\notes.txt", "timestampFormat": "yyyy-MM-dd HH:mm" } }
;
; Shows: an action with an optional parameter (bound from config or prompted
; for), paths expanded with Paths.Expand, and a helper in a subfolder.
App.AddPlugin("quickNote", (settings) => QuickNotePlugin.Init(settings))

class QuickNotePlugin {
    static File := ""
    static TimestampFormat := ""

    static Init(settings) {
        QuickNotePlugin.File := Paths.Expand(MapGet(settings, "file", "~\Documents\notes.txt"))
        QuickNotePlugin.TimestampFormat := MapGet(settings, "timestampFormat", "yyyy-MM-dd HH:mm")

        ActionRegistry.Register("quickNote.add", (text := unset) => QuickNotePlugin.Add(text?),
            { module: "plugin:quickNote", description: "Append a timestamped note (prompts when no text is given)", params: "[text]" })
        ActionRegistry.Register("quickNote.open", (*) => QuickNotePlugin.Open(),
            { module: "plugin:quickNote", description: "Open the notes file" })
    }

    static Add(text := unset) {
        if !IsSet(text) {
            answer := InputBox("Note:", "Quick note", "w420 h110")
            if (answer.Result != "OK")
                return
            text := answer.Value
        }
        line := NoteFormat.Line(text, FormatTime(, QuickNotePlugin.TimestampFormat))
        if (line = "")
            return
        QuickNotePlugin.EnsureFile()
        FileAppend(line, QuickNotePlugin.File, "UTF-8")
        Toast.ShowToast({ fadeDelay: 800 }, "Note saved")
    }

    static Open() {
        QuickNotePlugin.EnsureFile()
        Run(QuickNotePlugin.File)
    }

    static EnsureFile() {
        SplitPath(QuickNotePlugin.File, , &dir)
        if (dir != "" && !DirExist(dir))
            DirCreate(dir)
        if !FileExist(QuickNotePlugin.File)
            FileAppend("", QuickNotePlugin.File, "UTF-8")
    }
}
