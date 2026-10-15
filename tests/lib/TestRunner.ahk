#Requires AutoHotkey v2.0

; Minimal headless xUnit runner for AutoHotkey v2.
;
; A test class has static methods named Test_*; optional static Setup()/Teardown()
; run around each test. Register classes with TestRunner.Add(ClassName) and call
; TestRunner.Run() to print TAP output to stdout and exit 0 (pass) or 1 (fail).
;
;   class HotkeyText_Tests {
;       static Test_Format() => Assert.Equal("RCtrl+PgUp", HotkeyText.Format(">^PgUp"))
;   }
;   TestRunner.Add(HotkeyText_Tests)
class TestRunner {
    static Classes := []
    static Filter := ""

    static Add(cls) => TestRunner.Classes.Push(cls)

    static Run() {
        OnError((err, mode) => TestRunner._OnError(err, mode))
        for arg in A_Args {
            if (SubStr(arg, 1, 9) = "--filter=")
                TestRunner.Filter := SubStr(arg, 10)
        }
        tests := []
        for cls in TestRunner.Classes {
            for name in cls.OwnProps() {
                if (SubStr(name, 1, 5) != "Test_" || !HasMethod(cls, name))
                    continue
                full := cls.Prototype.__Class "." name
                if (TestRunner.Filter != "" && !InStr(full, TestRunner.Filter))
                    continue
                tests.Push({ cls: cls, name: name, full: full })
            }
        }
        TestRunner.Out("TAP version 13`n1.." tests.Length "`n")
        failed := 0
        for i, t in tests {
            try {
                if HasMethod(t.cls, "Setup")
                    t.cls.Setup()
                t.cls.%t.name%()
                TestRunner.Out("ok " i " - " t.full "`n")
            } catch as e {
                failed++
                TestRunner.Out("not ok " i " - " t.full "`n  # " StrReplace(e.Message, "`n", "`n  # ")
                    "`n  # at " e.File ":" e.Line "`n")
            } finally {
                if HasMethod(t.cls, "Teardown")
                    try t.cls.Teardown()
            }
        }
        TestRunner.Out("# " (tests.Length - failed) "/" tests.Length " passed`n")
        ExitApp(failed ? 1 : 0)
    }

    static Out(text) => FileAppend(text, "*", "UTF-8")

    static _OnError(err, mode) {
        TestRunner.Out("Bail out! " err.Message " (" err.File ":" err.Line ")`n")
        ExitApp(2)
    }
}

class Assert {
    static Fail(message) {
        throw AssertionError(message)
    }

    static True(value, message := "expected truthy value") {
        if !value
            Assert.Fail(message)
    }

    static False(value, message := "expected falsy value") {
        if value
            Assert.Fail(message)
    }

    static Equal(expected, actual, message := "") {
        if !Assert._Same(expected, actual)
            Assert.Fail((message != "" ? message ": " : "") "expected <" Assert.Show(expected) "> but got <" Assert.Show(actual) ">")
    }

    static NotEqual(unexpected, actual, message := "") {
        if Assert._Same(unexpected, actual)
            Assert.Fail((message != "" ? message ": " : "") "did not expect <" Assert.Show(actual) ">")
    }

    static Near(expected, actual, tolerance := 0.0001) {
        if (Abs(expected - actual) > tolerance)
            Assert.Fail("expected ~" expected " but got " actual)
    }

    static Contains(haystack, needle) {
        if (haystack is Array) {
            for v in haystack {
                if Assert._Same(v, needle)
                    return
            }
            Assert.Fail("array " Assert.Show(haystack) " does not contain <" Assert.Show(needle) ">")
        }
        if !InStr(haystack, needle, true)
            Assert.Fail("<" haystack "> does not contain <" needle ">")
    }

    ; Asserts fn throws; optionally that the message contains `fragment`.
    static Throws(fn, fragment := "") {
        try {
            fn.Call()
        } catch as e {
            if (e is AssertionError)
                throw e
            if (fragment != "" && !InStr(e.Message, fragment))
                Assert.Fail("error message <" e.Message "> does not contain <" fragment ">")
            return e
        }
        Assert.Fail("expected an error")
    }

    static _Same(a, b) {
        if (IsObject(a) || IsObject(b)) {
            if (a is Array && b is Array) {
                if (a.Length != b.Length)
                    return false
                loop a.Length {
                    if !Assert._Same(a[A_Index], b[A_Index])
                        return false
                }
                return true
            }
            if (a is Map && b is Map) {
                if (a.Count != b.Count)
                    return false
                for k, v in a {
                    if !b.Has(k) || !Assert._Same(v, b[k])
                        return false
                }
                return true
            }
            return a == b
        }
        return Type(a) = Type(b) ? a == b : (IsNumber(a) && IsNumber(b) ? a = b : String(a) == String(b))
    }

    static Show(v) {
        if (v is Array) {
            out := "["
            for i, x in v
                out .= (i = 1 ? "" : ", ") Assert.Show(x)
            return out "]"
        }
        if (v is Map) {
            out := "{"
            for k, x in v
                out .= (A_Index = 1 ? "" : ", ") k ": " Assert.Show(x)
            return out "}"
        }
        return IsObject(v) ? "<" Type(v) ">" : String(v)
    }
}

class AssertionError extends Error {
}
