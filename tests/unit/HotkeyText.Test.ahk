#Requires AutoHotkey v2.0

class HotkeyText_Tests {
    static Test_ParseSidedModifiers() {
        p := HotkeyText.Parse(">^>!<+PgUp")
        Assert.Equal(["RCtrl", "RAlt", "LShift"], p.mods)
        Assert.Equal("PgUp", p.key)
        Assert.False(p.up)
    }

    static Test_ParseUnsidedModifiers() {
        p := HotkeyText.Parse("^+Insert")
        Assert.Equal(["Ctrl", "Shift"], p.mods)
        Assert.Equal("Insert", p.key)
    }

    static Test_ParseReleaseSuffix() {
        p := HotkeyText.Parse("^+Insert UP")
        Assert.True(p.up)
        Assert.Equal("Insert", p.key)
    }

    static Test_ParseCustomCombination() {
        p := HotkeyText.Parse("LShift & Volume_Up")
        Assert.Equal(["LShift"], p.mods)
        Assert.Equal("Volume_Up", p.key)
    }

    static Test_ParsePrefixFlags() {
        p := HotkeyText.Parse("~*$Space")
        Assert.True(p.wildcard)
        Assert.True(p.passThrough)
        Assert.Equal("Space", p.key)
    }

    static Test_ParseSymbolKeys() {
        Assert.Equal("=", HotkeyText.Parse("#=").key)
        Assert.Equal("=", HotkeyText.Parse("#+=").key)
        Assert.Equal(["Win", "Shift"], HotkeyText.Parse("#+=").mods)
        ; A modifier symbol used as the key itself.
        Assert.Equal("+", HotkeyText.Parse("^+").key)
        Assert.Equal("-", HotkeyText.Parse("#-").key)
    }

    static Test_BaseKey() {
        Assert.Equal("F23", HotkeyText.BaseKey(">!<#<+F23"))
        Assert.Equal("Space", HotkeyText.BaseKey("+Space"))
    }

    static Test_FormatReadable() {
        Assert.Equal("RCtrl+RAlt+PgUp", HotkeyText.Format(">^>!PgUp"))
        Assert.Equal("Win+Shift+=", HotkeyText.Format("#+="))
        Assert.Equal("LShift+Mute", HotkeyText.Format("LShift & Volume_Mute"))
        Assert.Equal("Ctrl+Shift+Insert (release)", HotkeyText.Format("^+Insert UP"))
    }

    static Test_FormatWithLayerAndSingleLetter() {
        Assert.Equal("CapsLock+Ctrl+C", HotkeyText.Format("^c", "CapsLock"))
        Assert.Equal("CapsLock+LCtrl+C", HotkeyText.Format("<^c", "CapsLock"))
    }

    static Test_ToSendEvent() {
        Assert.Equal("{RShift down}{F24}{RShift up}", HotkeyText.ToSendEvent(">+F24"))
        Assert.Equal("{LCtrl down}{F22}{LCtrl up}", HotkeyText.ToSendEvent("^F22"))
        Assert.Equal("{RCtrl down}{RAlt down}{F13}{RAlt up}{RCtrl up}", HotkeyText.ToSendEvent(">^>!F13"))
    }

    static Test_AppUtilDelegates() {
        Assert.Equal(HotkeyText.ToSendEvent("<#<+F23"), AppUtil.HotkeyToSendEvent("<#<+F23"))
    }

    static Test_ParseDefaultsHaveNoPrefixFlags() {
        p := HotkeyText.Parse("F1")
        Assert.False(p.wildcard)
        Assert.False(p.passThrough)
        Assert.False(p.up)
        Assert.Equal([], p.mods)
    }
}
TestRunner.Add(HotkeyText_Tests)
