#Requires AutoHotkey v2.0

class Toast {
    ; ==================== Toast Utilities ====================
    ;
    ; Lightweight, configurable toast notifications rendered at lower-center.
    ; Usage:
    ;   ShowToast({ text: "⏯", size: 24 }, { text: "Play/Pause", size: 14 })
    ; Each argument may be:
    ;   - String: rendered with defaults
    ;   - Object: keys: text, size, color, name, bold, italic, spacing, width, align
    ;
    ; Notes:
    ;   - Automatically destroys the previous toast to avoid overlap
    ;   - Requests rounded corners via DWM (safe no-op if unsupported)
    ;   - Fades out smoothly, then destroys
    static ShowToast_Destroy(gui) {
        ; Safely destroy a GUI if it exists (ignore errors)
        try {
            if (IsObject(gui))
                gui.Destroy()
        }
    }

    static ShowToast_ApplyRoundedCorners(hwnd) {
        ; Ask DWM for rounded corners (Windows 11+). No-op if unsupported.
        DWMWCP_ROUND := 2 ; DWM_WINDOW_CORNER_PREFERENCE: round small
        try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 33, "int*", DWMWCP_ROUND, "int", 4)
    }

    static ShowToast_FadeOut(gui, startOpacity := 178, step := 30, interval := 25) {
        ; Begin fade-out lifecycle for a toast GUI
        try hwnd := gui.Hwnd
        catch
            return
        if !WinExist("ahk_id " hwnd)
            return

        gui.Opacity := startOpacity
        SetTimer(() => Toast.ShowToast_FadeStep(gui, step, interval), -interval)
    }

    static ShowToast_FadeStep(gui, step, interval, *) {
        ; Lower opacity and reschedule until destroyed
        try hwnd := gui.Hwnd
        catch
            return
        if !WinExist("ahk_id " hwnd)
            return

        gui.Opacity -= step
        if (gui.Opacity <= 0) {
            gui.Destroy()
            return
        }

        WinSetTransparent(gui.Opacity, hwnd)
        SetTimer(() => Toast.ShowToast_FadeStep(gui, step, interval), -interval)
    }

    static ShowToast(options := unset, lines*) {
        ; Render a toast at lower-center with per-line configuration
        static LastToast := 0
        prev := LastToast
        Toast.ShowToast_Destroy(prev)

        newGui := Gui("+AlwaysOnTop +ToolWindow -Caption +DPIScale")
        ; Resolve defaults (allow overrides via defaultOpts)
        marginX := 16
        marginY := 16
        defaultSize := 12
        defaultColor := "E8E8E8"
        defaultWidth := 130
        defaultAlign := "Center"
        backColor := "2D2D2D"
        opacity := Round(255 * 0.9)
        bottomPct := 0.20  ; distance from bottom edge (0.20 = 20%)
        fadeDelay := 1500
        fadeStep := 30
        fadeInterval := 25

        if IsSet(options) && IsObject(options) {
            if options.HasProp("marginX")
                marginX := options.marginX
            if options.HasProp("marginY")
                marginY := options.marginY
            if options.HasProp("size")
                defaultSize := options.size
            if options.HasProp("color")
                defaultColor := options.color
            if options.HasProp("width")
                defaultWidth := options.width
            if options.HasProp("align")
                defaultAlign := options.align
            if options.HasProp("backColor")
                backColor := options.backColor
            if options.HasProp("opacity")
                opacity := options.opacity
            if options.HasProp("bottomPct")
                bottomPct := options.bottomPct
            if options.HasProp("fadeDelay")
                fadeDelay := options.fadeDelay
            if options.HasProp("fadeStep")
                fadeStep := options.fadeStep
            if options.HasProp("fadeInterval")
                fadeInterval := options.fadeInterval
        }

        newGui.MarginX := marginX
        newGui.MarginY := marginY

        for idx, line in lines {
            text := ""
            size := defaultSize
            color := defaultColor
            width := defaultWidth
            align := defaultAlign
            spacing := idx > 1 ? 12 : 0
            name := ""
            bold := false
            italic := false

            if (Type(line) = "String") {
                text := line
            } else if IsObject(line) {
                if line.HasProp("text")
                    text := line.text
                if line.HasProp("size")
                    size := line.size
                if line.HasProp("color")
                    color := line.color
                if line.HasProp("width")
                    width := line.width
                if line.HasProp("align")
                    align := line.align
                if line.HasProp("spacing")
                    spacing := line.spacing
                if line.HasProp("name")
                    name := line.name
                if line.HasProp("bold")
                    bold := !!line.bold
                if line.HasProp("italic")
                    italic := !!line.italic
            }

            opt := "s" size " c" color
            if bold
                opt := opt " Bold"
            if italic
                opt := opt " Italic"

            if (name != "")
                newGui.SetFont(opt, name)
            else
                newGui.SetFont(opt)

            ctrlOpts := "w" width " " align
            if (spacing && spacing > 0)
                ctrlOpts := "y+" spacing " " ctrlOpts

            newGui.Add("Text", ctrlOpts, text)
        }

        Y := A_ScreenHeight - (A_ScreenHeight * bottomPct)
        newGui.BackColor := backColor
        newGui.Show("xCenter y" . Y . " NoActivate")

        Toast.ShowToast_ApplyRoundedCorners(newGui.Hwnd)
        WinSetTransparent(opacity, newGui.Hwnd)
        SetTimer(() => Toast.ShowToast_FadeOut(newGui, opacity, fadeStep, fadeInterval), -fadeDelay)
        LastToast := newGui
    }
}
