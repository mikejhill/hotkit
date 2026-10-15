#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon

; Opens two windows that the fixture's "e2ewin" app matches, plus one that it
; doesn't, for the app toggle test. Exits on its own.
for title in ["hotkit-e2e-win A", "hotkit-e2e-win B", "hotkit-e2e-other"] {
    g := Gui("+Resize", title)
    g.Add("Text", "w200", title)
    g.Show("w240 h80 x" (40 + A_Index * 60) " y" (40 + A_Index * 60))
}
SetTimer(() => ExitApp(), -90000)
