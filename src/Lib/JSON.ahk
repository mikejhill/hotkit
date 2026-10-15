#Requires AutoHotkey v2.0

; ==================== JSON Parser / Serializer ====================
;
; Pure AHK v2 JSON library — no external dependencies, no spawned processes.
; Performance-conscious: uses direct UTF-16 code-unit reads via StrPtr/NumGet,
; bulk slice extraction with StrGet, and array-buffered output assembly.
;
; Public API
;   JSON.Parse(text, options?)        -> value
;   JSON.Stringify(value, options?)   -> text
;
; Parse options (object literal):
;   allowComments       (Bool, default false)  Allow '// ...' and '/* ... */'
;   allowTrailingCommas (Bool, default false)  Allow ',' before '}' or ']'
;
; Stringify options (object literal):
;   pretty   (Bool,   default false) Insert newlines and indentation
;   indent   (String, default "  ")  Indent string used per nesting level
;   newline  (String, default "`n")  Newline string used in pretty mode
;
; Type mapping
;   JSON object  <->  Map      (keys enumerate in sorted order)
;   JSON array   <->  Array
;   JSON string  <->  String
;   JSON number  <->  Integer or Float
;   JSON true    <->  JSON.True   (sentinel object)
;   JSON false   <->  JSON.False  (sentinel object)
;   JSON null    <->  JSON.Null   (sentinel object)
;
; Boolean / null handling
;   AHK v2 has no distinct Boolean or Null type, so sentinels are used to
;   avoid the ambiguity between JSON `true`/`false`/`null` and the AHK
;   integers 1/0/"". Parse always produces these sentinels; Stringify emits
;   the matching JSON literal when it sees them. Native AHK numbers and
;   strings are serialized as numbers / strings (so `Stringify(1)` -> "1",
;   not "true"). Use `JSON.True` / `JSON.False` / `JSON.Null` to write
;   JSON booleans / null. Plain {key: value} objects are also accepted on
;   the serialize side and treated as JSON objects.

class JSON {
    ; ---------------- Sentinel singletons ----------------
    static True := { __jsonLiteral: "true" }
    static False := { __jsonLiteral: "false" }
    static Null := { __jsonLiteral: "null" }

    ; ==================== Public: Parse ====================
    static Parse(text, options?) {
        opts := JSON._BuildParseOptions(options?)
        ctx := {
            text: text,
            ptr: StrPtr(text),
            pos: 0,
            len: StrLen(text),
            opts: opts,
        }
        JSON._SkipWS(ctx)
        if (ctx.pos >= ctx.len) {
            throw ValueError("JSON.Parse: empty input")
        }
        value := JSON._ParseValue(ctx)
        JSON._SkipWS(ctx)
        if (ctx.pos < ctx.len) {
            JSON._Throw(ctx, "Unexpected trailing content")
        }
        return value
    }

    ; ==================== Public: Stringify ====================
    static Stringify(value, options?) {
        opts := JSON._BuildStringifyOptions(options?)
        parts := []
        JSON._Write(value, parts, opts, 0)
        ; Bulk join (faster than running concatenation across the recursion)
        result := ""
        for _, chunk in parts {
            result .= chunk
        }
        return result
    }

    ; =============== Internal: option building ===============
    static _BuildParseOptions(override?) {
        opts := {
            allowComments: false,
            allowTrailingCommas: false,
        }
        if (IsSet(override)) {
            for k, v in override.OwnProps() {
                opts.%k% := v
            }
        }
        return opts
    }

    static _BuildStringifyOptions(override?) {
        opts := {
            pretty: false,
            indent: "  ",
            newline: "`n",
        }
        if (IsSet(override)) {
            for k, v in override.OwnProps() {
                opts.%k% := v
            }
        }
        return opts
    }

    ; ==================== Parser core ====================
    static _Throw(ctx, message) {
        ; Compute line/column for diagnostics
        line := 1
        col := 1
        i := 0
        while (i < ctx.pos && i < ctx.len) {
            ch := NumGet(ctx.ptr, i * 2, "UShort")
            if (ch = 0x0A) {
                line += 1
                col := 1
            } else if (ch != 0x0D) {
                col += 1
            }
            i += 1
        }
        throw ValueError("JSON.Parse: " message " (line " line ", col " col ")")
    }

    static _SkipWS(ctx) {
        opts := ctx.opts
        ptr := ctx.ptr
        len := ctx.len
        pos := ctx.pos
        allowComments := opts.allowComments
        loop {
            ; Whitespace
            while (pos < len) {
                ch := NumGet(ptr, pos * 2, "UShort")
                if (ch != 0x20 && ch != 0x09 && ch != 0x0A && ch != 0x0D) {
                    break
                }
                pos += 1
            }
            if (!allowComments || pos >= len) {
                ctx.pos := pos
                return
            }
            if (NumGet(ptr, pos * 2, "UShort") != 0x2F) {  ; '/'
                ctx.pos := pos
                return
            }
            if (pos + 1 >= len) {
                ctx.pos := pos
                return
            }
            next := NumGet(ptr, (pos + 1) * 2, "UShort")
            if (next = 0x2F) {
                ; Line comment '// ...'
                pos += 2
                while (pos < len) {
                    ch := NumGet(ptr, pos * 2, "UShort")
                    if (ch = 0x0A || ch = 0x0D) {
                        break
                    }
                    pos += 1
                }
            } else if (next = 0x2A) {
                ; Block comment '/* ... */'
                pos += 2
                terminated := false
                while (pos + 1 < len) {
                    if (NumGet(ptr, pos * 2, "UShort") = 0x2A
                        && NumGet(ptr, (pos + 1) * 2, "UShort") = 0x2F) {
                        pos += 2
                        terminated := true
                        break
                    }
                    pos += 1
                }
                if (!terminated) {
                    ctx.pos := pos
                    JSON._Throw(ctx, "Unterminated block comment")
                }
            } else {
                ctx.pos := pos
                return
            }
        }
    }

    static _ParseValue(ctx) {
        if (ctx.pos >= ctx.len) {
            JSON._Throw(ctx, "Unexpected end of input")
        }
        ch := NumGet(ctx.ptr, ctx.pos * 2, "UShort")
        switch ch {
            case 0x7B: return JSON._ParseObject(ctx)                    ; '{'
            case 0x5B: return JSON._ParseArray(ctx)                     ; '['
            case 0x22: return JSON._ParseString(ctx)                    ; '"'
            case 0x74: return JSON._ParseLiteral(ctx, "true", JSON.True)
            case 0x66: return JSON._ParseLiteral(ctx, "false", JSON.False)
            case 0x6E: return JSON._ParseLiteral(ctx, "null", JSON.Null)
        }
        if (ch = 0x2D || (ch >= 0x30 && ch <= 0x39)) {                  ; '-' or '0'..'9'
            return JSON._ParseNumber(ctx)
        }
        JSON._Throw(ctx, "Unexpected character '" Chr(ch) "'")
    }

    static _ParseObject(ctx) {
        ctx.pos += 1  ; consume '{'
        result := Map()
        JSON._SkipWS(ctx)
        if (ctx.pos < ctx.len && NumGet(ctx.ptr, ctx.pos * 2, "UShort") = 0x7D) {
            ctx.pos += 1  ; '}'
            return result
        }
        loop {
            JSON._SkipWS(ctx)
            if (ctx.opts.allowTrailingCommas
                && ctx.pos < ctx.len
                && NumGet(ctx.ptr, ctx.pos * 2, "UShort") = 0x7D) {
                ctx.pos += 1
                return result
            }
            if (ctx.pos >= ctx.len
                || NumGet(ctx.ptr, ctx.pos * 2, "UShort") != 0x22) {
                JSON._Throw(ctx, "Expected string key")
            }
            key := JSON._ParseString(ctx)
            JSON._SkipWS(ctx)
            if (ctx.pos >= ctx.len
                || NumGet(ctx.ptr, ctx.pos * 2, "UShort") != 0x3A) {
                JSON._Throw(ctx, "Expected ':' after key")
            }
            ctx.pos += 1  ; ':'
            JSON._SkipWS(ctx)
            result[key] := JSON._ParseValue(ctx)
            JSON._SkipWS(ctx)
            if (ctx.pos >= ctx.len) {
                JSON._Throw(ctx, "Unterminated object")
            }
            ch := NumGet(ctx.ptr, ctx.pos * 2, "UShort")
            if (ch = 0x7D) {
                ctx.pos += 1
                return result
            }
            if (ch != 0x2C) {
                JSON._Throw(ctx, "Expected ',' or '}' in object")
            }
            ctx.pos += 1  ; ','
        }
    }

    static _ParseArray(ctx) {
        ctx.pos += 1  ; consume '['
        result := []
        JSON._SkipWS(ctx)
        if (ctx.pos < ctx.len && NumGet(ctx.ptr, ctx.pos * 2, "UShort") = 0x5D) {
            ctx.pos += 1  ; ']'
            return result
        }
        loop {
            JSON._SkipWS(ctx)
            if (ctx.opts.allowTrailingCommas
                && ctx.pos < ctx.len
                && NumGet(ctx.ptr, ctx.pos * 2, "UShort") = 0x5D) {
                ctx.pos += 1
                return result
            }
            result.Push(JSON._ParseValue(ctx))
            JSON._SkipWS(ctx)
            if (ctx.pos >= ctx.len) {
                JSON._Throw(ctx, "Unterminated array")
            }
            ch := NumGet(ctx.ptr, ctx.pos * 2, "UShort")
            if (ch = 0x5D) {
                ctx.pos += 1
                return result
            }
            if (ch != 0x2C) {
                JSON._Throw(ctx, "Expected ',' or ']' in array")
            }
            ctx.pos += 1  ; ','
        }
    }

    static _ParseString(ctx) {
        ctx.pos += 1  ; opening '"'
        ptr := ctx.ptr
        len := ctx.len
        start := ctx.pos
        pos := start
        ; Fast path: scan ahead until '"', '\', or invalid control char
        while (pos < len) {
            ch := NumGet(ptr, pos * 2, "UShort")
            if (ch = 0x22) {  ; '"'
                result := (pos > start) ? StrGet(ptr + start * 2, pos - start, "UTF-16") : ""
                ctx.pos := pos + 1
                return result
            }
            if (ch = 0x5C) {  ; '\'
                break
            }
            if (ch < 0x20) {
                ctx.pos := pos
                JSON._Throw(ctx, "Unescaped control character in string")
            }
            pos += 1
        }
        if (pos >= len) {
            ctx.pos := pos
            JSON._Throw(ctx, "Unterminated string")
        }
        ; Slow path: string contains escapes
        prefix := (pos > start) ? StrGet(ptr + start * 2, pos - start, "UTF-16") : ""
        ctx.pos := pos
        return prefix . JSON._ParseStringEscaped(ctx)
    }

    static _ParseStringEscaped(ctx) {
        ptr := ctx.ptr
        len := ctx.len
        pos := ctx.pos
        runStart := pos
        out := ""
        loop {
            if (pos >= len) {
                ctx.pos := pos
                JSON._Throw(ctx, "Unterminated string")
            }
            ch := NumGet(ptr, pos * 2, "UShort")
            if (ch = 0x22) {  ; '"'
                if (pos > runStart) {
                    out .= StrGet(ptr + runStart * 2, pos - runStart, "UTF-16")
                }
                ctx.pos := pos + 1
                return out
            }
            if (ch = 0x5C) {  ; '\'
                if (pos > runStart) {
                    out .= StrGet(ptr + runStart * 2, pos - runStart, "UTF-16")
                }
                pos += 1
                if (pos >= len) {
                    ctx.pos := pos
                    JSON._Throw(ctx, "Unterminated escape")
                }
                esc := NumGet(ptr, pos * 2, "UShort")
                switch esc {
                    case 0x22: out .= '"'
                    case 0x5C: out .= "\"
                    case 0x2F: out .= "/"
                    case 0x62: out .= "`b"
                    case 0x66: out .= "`f"
                    case 0x6E: out .= "`n"
                    case 0x72: out .= "`r"
                    case 0x74: out .= "`t"
                    case 0x75:
                        if (pos + 4 >= len) {
                            ctx.pos := pos
                            JSON._Throw(ctx, "Invalid \u escape")
                        }
                        hex := StrGet(ptr + (pos + 1) * 2, 4, "UTF-16")
                        if (!RegExMatch(hex, "^[0-9A-Fa-f]{4}$")) {
                            ctx.pos := pos
                            JSON._Throw(ctx, "Invalid \u escape")
                        }
                        ; Emit raw UTF-16 code unit; surrogate pairs naturally
                        ; assemble into supplementary characters when two
                        ; consecutive \uXXXX escapes are processed.
                        out .= Chr(Integer("0x" hex))
                        pos += 4
                    default:
                        ctx.pos := pos
                        JSON._Throw(ctx, "Invalid escape sequence")
                }
                pos += 1
                runStart := pos
            } else if (ch < 0x20) {
                ctx.pos := pos
                JSON._Throw(ctx, "Unescaped control character in string")
            } else {
                pos += 1
            }
        }
    }

    static _ParseNumber(ctx) {
        ptr := ctx.ptr
        len := ctx.len
        start := ctx.pos
        pos := start
        numIsFloat := false

        ch := NumGet(ptr, pos * 2, "UShort")
        if (ch = 0x2D) {  ; '-'
            pos += 1
            if (pos >= len) {
                ctx.pos := pos
                JSON._Throw(ctx, "Invalid number")
            }
            ch := NumGet(ptr, pos * 2, "UShort")
        }
        ; Integer part: '0' alone or [1-9][0-9]*
        if (ch = 0x30) {
            pos += 1
        } else if (ch >= 0x31 && ch <= 0x39) {
            pos += 1
            while (pos < len) {
                ch := NumGet(ptr, pos * 2, "UShort")
                if (ch < 0x30 || ch > 0x39) {
                    break
                }
                pos += 1
            }
        } else {
            ctx.pos := pos
            JSON._Throw(ctx, "Invalid number")
        }
        ; Fraction
        if (pos < len && NumGet(ptr, pos * 2, "UShort") = 0x2E) {  ; '.'
            numIsFloat := true
            pos += 1
            digits := 0
            while (pos < len) {
                ch := NumGet(ptr, pos * 2, "UShort")
                if (ch < 0x30 || ch > 0x39) {
                    break
                }
                pos += 1
                digits += 1
            }
            if (digits = 0) {
                ctx.pos := pos
                JSON._Throw(ctx, "Invalid number (expected digits after '.')")
            }
        }
        ; Exponent
        if (pos < len) {
            ch := NumGet(ptr, pos * 2, "UShort")
            if (ch = 0x65 || ch = 0x45) {  ; 'e' / 'E'
                numIsFloat := true
                pos += 1
                if (pos < len) {
                    ch := NumGet(ptr, pos * 2, "UShort")
                    if (ch = 0x2B || ch = 0x2D) {  ; '+' / '-'
                        pos += 1
                    }
                }
                digits := 0
                while (pos < len) {
                    ch := NumGet(ptr, pos * 2, "UShort")
                    if (ch < 0x30 || ch > 0x39) {
                        break
                    }
                    pos += 1
                    digits += 1
                }
                if (digits = 0) {
                    ctx.pos := pos
                    JSON._Throw(ctx, "Invalid number (expected digits in exponent)")
                }
            }
        }
        text := StrGet(ptr + start * 2, pos - start, "UTF-16")
        ctx.pos := pos
        return numIsFloat ? Float(text) : Integer(text)
    }

    static _ParseLiteral(ctx, expected, value) {
        n := StrLen(expected)
        if (ctx.pos + n > ctx.len) {
            JSON._Throw(ctx, "Unexpected token")
        }
        actual := StrGet(ctx.ptr + ctx.pos * 2, n, "UTF-16")
        if (actual != expected) {
            JSON._Throw(ctx, "Expected '" expected "'")
        }
        ctx.pos += n
        return value
    }

    ; ==================== Serializer core ====================
    static _Write(value, parts, opts, depth) {
        t := Type(value)
        if (t = "Integer") {
            parts.Push(String(value))
            return
        }
        if (t = "Float") {
            parts.Push(JSON._FormatFloat(value))
            return
        }
        if (t = "String") {
            JSON._WriteString(value, parts)
            return
        }
        ; Object types
        if (value = JSON.Null) {
            parts.Push("null")
            return
        }
        if (value = JSON.True) {
            parts.Push("true")
            return
        }
        if (value = JSON.False) {
            parts.Push("false")
            return
        }
        if (value is Map) {
            JSON._WriteMap(value, parts, opts, depth)
            return
        }
        if (value is Array) {
            JSON._WriteArray(value, parts, opts, depth)
            return
        }
        ; Plain object literal: serialize its OwnProps
        JSON._WriteOwnProps(value, parts, opts, depth)
    }

    static _FormatFloat(v) {
        ; Compact, JSON-compatible float rendering. Avoids printf-style
        ; trailing zeros while preserving precision.
        return Format("{:g}", v)
    }

    static _WriteMap(map, parts, opts, depth) {
        pretty := opts.pretty
        newline := opts.newline
        indent := opts.indent
        nextDepth := depth + 1
        parts.Push("{")
        wroteAny := false
        for k, v in map {
            if (wroteAny) {
                parts.Push(",")
            }
            if (pretty) {
                parts.Push(newline)
                JSON._WriteIndent(parts, indent, nextDepth)
            }
            JSON._WriteString(String(k), parts)
            parts.Push(pretty ? ": " : ":")
            JSON._Write(v, parts, opts, nextDepth)
            wroteAny := true
        }
        if (wroteAny && pretty) {
            parts.Push(newline)
            JSON._WriteIndent(parts, indent, depth)
        }
        parts.Push("}")
    }

    static _WriteArray(arr, parts, opts, depth) {
        pretty := opts.pretty
        newline := opts.newline
        indent := opts.indent
        nextDepth := depth + 1
        parts.Push("[")
        wroteAny := false
        for _, v in arr {
            if (wroteAny) {
                parts.Push(",")
            }
            if (pretty) {
                parts.Push(newline)
                JSON._WriteIndent(parts, indent, nextDepth)
            }
            JSON._Write(v, parts, opts, nextDepth)
            wroteAny := true
        }
        if (wroteAny && pretty) {
            parts.Push(newline)
            JSON._WriteIndent(parts, indent, depth)
        }
        parts.Push("]")
    }

    static _WriteOwnProps(obj, parts, opts, depth) {
        pretty := opts.pretty
        newline := opts.newline
        indent := opts.indent
        nextDepth := depth + 1
        parts.Push("{")
        wroteAny := false
        for k, v in obj.OwnProps() {
            if (wroteAny) {
                parts.Push(",")
            }
            if (pretty) {
                parts.Push(newline)
                JSON._WriteIndent(parts, indent, nextDepth)
            }
            JSON._WriteString(k, parts)
            parts.Push(pretty ? ": " : ":")
            JSON._Write(v, parts, opts, nextDepth)
            wroteAny := true
        }
        if (wroteAny && pretty) {
            parts.Push(newline)
            JSON._WriteIndent(parts, indent, depth)
        }
        parts.Push("}")
    }

    static _WriteIndent(parts, indent, depth) {
        if (depth <= 0 || indent = "") {
            return
        }
        s := ""
        loop depth {
            s .= indent
        }
        parts.Push(s)
    }

    static _WriteString(s, parts) {
        ; Bulk-copy runs of safe characters, escape special ones inline.
        ptr := StrPtr(s)
        len := StrLen(s)
        runStart := 0
        pos := 0
        out := '"'
        while (pos < len) {
            ch := NumGet(ptr, pos * 2, "UShort")
            replacement := ""
            if (ch = 0x22) {
                replacement := '\"'
            } else if (ch = 0x5C) {
                replacement := "\\"
            } else if (ch < 0x20) {
                switch ch {
                    case 0x08: replacement := "\b"
                    case 0x09: replacement := "\t"
                    case 0x0A: replacement := "\n"
                    case 0x0C: replacement := "\f"
                    case 0x0D: replacement := "\r"
                    default: replacement := Format("\u{:04x}", ch)
                }
            }
            if (replacement != "") {
                if (pos > runStart) {
                    out .= StrGet(ptr + runStart * 2, pos - runStart, "UTF-16")
                }
                out .= replacement
                pos += 1
                runStart := pos
            } else {
                pos += 1
            }
        }
        if (pos > runStart) {
            out .= StrGet(ptr + runStart * 2, pos - runStart, "UTF-16")
        }
        out .= '"'
        parts.Push(out)
    }
}
