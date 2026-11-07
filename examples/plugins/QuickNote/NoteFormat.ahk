#Requires AutoHotkey v2.0

; Decisions for the QuickNote example plugin. No file or UI access, so it can be unit tested.
class NoteFormat {
    ; One note per line: line breaks become spaces, surrounding space is trimmed,
    ; and blank text yields "" (nothing to write).
    static Line(text, stamp) {
        flat := Trim(RegExReplace(text, "\s*[\r\n]+\s*", " "))
        return flat = "" ? "" : stamp "  " flat "`n"
    }
}
