#Requires AutoHotkey v2.0

class DisplayMath_Tests {
    static Test_GammaCurve() {
        Assert.Equal(1.0, GammaBrightness.GammaFor(100.0))
        Assert.Near(2.0, GammaBrightness.GammaFor(50.0))
        Assert.Near(3.0, GammaBrightness.GammaFor(0.0))
        Assert.Near(0.6, GammaBrightness.GammaFor(200.0))
        Assert.Near(0.2, GammaBrightness.GammaFor(300.0))
    }

    static Test_GammaStepsUp() {
        Assert.Equal(87.5, GammaBrightness.NextLevel(85.0, 1))
        Assert.Equal(100.0, GammaBrightness.NextLevel(97.5, 1))
        Assert.Equal(105.0, GammaBrightness.NextLevel(100.0, 1))
        Assert.Equal(90.0, GammaBrightness.NextLevel(88.0, 1), "snaps to the step grid")
        Assert.Equal(300.0, GammaBrightness.NextLevel(298.0, 1))
        Assert.Equal(300.0, GammaBrightness.NextLevel(300.0, 1))
    }

    static Test_GammaStepsDown() {
        Assert.Equal(97.5, GammaBrightness.NextLevel(100.0, -1))
        Assert.Equal(100.0, GammaBrightness.NextLevel(105.0, -1))
        Assert.Equal(85.0, GammaBrightness.NextLevel(86.0, -1))
        Assert.Equal(25.0, GammaBrightness.NextLevel(26.0, -1))
        Assert.Equal(25.0, GammaBrightness.NextLevel(25.0, -1))
    }

    static Test_NightLightKelvinRoundTrip() {
        Assert.Equal(6500.0, NightLight.KelvinFor(0))
        Assert.Equal(1200.0, NightLight.KelvinFor(100))
        Assert.Equal(1200.0, NightLight.KelvinFor(150), "clamped")
        for pct in [0, 5, 33, 50, 77, 100] {
            enc := NightLight.EncodeKelvin(NightLight.KelvinFor(pct))
            Assert.Equal(pct, NightLight.PercentFor(NightLight.DecodeKelvin(enc.lo, enc.hi)), "pct " pct)
        }
    }

    static Test_NightLightSteps() {
        Assert.Equal(55, NightLight.NextStrength(50, 5))
        Assert.Equal(55, NightLight.NextStrength(52, 5))
        Assert.Equal(50, NightLight.NextStrength(52, -5))
        Assert.Equal(100, NightLight.NextStrength(99, 5))
        Assert.Equal(0, NightLight.NextStrength(3, -5))
    }

    static Test_SwapRemembersLastLevel() {
        HardwareBrightness.LastSelected := 50
        HardwareBrightness.SwapFallback := 85
        Assert.Equal(0, HardwareBrightness.SwapTarget(40, 0))
        Assert.Equal(40, HardwareBrightness.LastSelected)
        Assert.Equal(40, HardwareBrightness.SwapTarget(0, 0))
        HardwareBrightness.LastSelected := 0
        Assert.Equal(85, HardwareBrightness.SwapTarget(0, 0), "falls back when last equals target")
        Assert.Equal(0, HardwareBrightness.SwapTarget(100, 0))
        Assert.Equal(0, HardwareBrightness.LastSelected, "0 and 100 are never remembered")
    }

    static Test_ScaleSteps() {
        presets := [150, 100, 125, 200]
        Assert.Equal(125, DisplayScale.StepBy(100, 1, presets))
        Assert.Equal(200, DisplayScale.StepBy(100, 9, presets))
        Assert.Equal(100, DisplayScale.StepBy(125, -3, presets))
        Assert.Equal(150, DisplayScale.StepBy(140, 1, presets), "off-grid values step from the preset below")
        Assert.Equal(137, DisplayScale.StepBy(137, 0, presets))
        Assert.Equal(100, DisplayScale.StepBy(50, 1, presets), "below the lowest preset")
    }

    static Test_ScaleHelpers() {
        Assert.Equal(150, DisplayScale.ParseScale("Current resolution scale: 150%"))
        Assert.Equal("", DisplayScale.ParseScale("nothing"))
        Assert.Equal([1, 2, 3], DisplayScale.SortNumeric([3, 1, 2]))
        Assert.Equal(125, DisplayScale.ValidateScale(125))
        Assert.Throws(() => DisplayScale.ValidateScale(20), "between")
        Assert.Throws(() => DisplayScale.ValidateScale("abc"), "integer")
    }

    static Test_ScaleBounds() {
        Assert.Equal(50, DisplayScale.ValidateScale(50))
        Assert.Equal(400, DisplayScale.ValidateScale(400))
        Assert.Throws(() => DisplayScale.ValidateScale(401), "between")
        Assert.Equal([100, 125, 125, 150], DisplayScale.SortNumeric([125, 150, 100, 125]))
    }
}
TestRunner.Add(DisplayMath_Tests)
