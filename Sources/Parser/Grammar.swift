//
//  Grammar.swift
//  Parser - Rego grammar productions, organised top-down by phase.
//
//  This file is intentionally large: reviewers should be able to scan the
//  whole grammar in one pass. Logic that doesn't directly express the
//  grammar (errors, types, source bookkeeping) lives in sibling files.
//
//  Phases (// MARK: sections below) follow the project plan:
//    1. Trivia, identifiers, reserved-word check, refs, package, module.
//    2. Lexical (scalars, strings, raw + template strings).      [TODO]
//    3. Terms (composites, comprehensions).                       [TODO]
//    4. Expressions (precedence, calls, every).                   [TODO]
//    5. Literals, with-modifiers, some-decl, not.                 [TODO]
//    6. Rule heads (set/obj/func/comp), bodies, else.             [TODO]
//    7. Imports.                                                  [TODO]
//

import Foundation
import Parsing

// MARK: - Reserved words

/// Per `policy-reference.md`. These must never bind as identifiers.
///
/// Note: `contains` is intentionally **not** in this set even though it
/// introduces set-rule heads. Upstream OPA accepts `contains` as a builtin
/// function name in expressions (e.g. `contains("hi", "h")`); the grammar
/// disambiguates by position — `contains` is recognised as a rule-head
/// keyword only when it appears immediately after a rule-head name. As a
/// regular identifier it parses through `parseVariable` like any other.
let reservedWords: Set<String> = [
    "as", "data", "default", "else", "every", "false",
    "if", "import", "in", "input", "not", "null", "package", "some",
    "true", "with",
]

// MARK: - Source position helper

/// Maps `String.Index` values into a parsed `Substring`'s parent string into
/// `SourceLocation` values. Pre-computes line starts on init so per-lookup
/// work is O(log n) lines.
struct LocationMapper {
    let contents: String
    private let lineStarts: [String.Index]

    init(contents: String) {
        var starts: [String.Index] = [contents.startIndex]
        var i = contents.startIndex
        while i < contents.endIndex {
            if contents[i] == "\n" {
                starts.append(contents.index(after: i))
            }
            i = contents.index(after: i)
        }
        self.contents = contents
        self.lineStarts = starts
    }

    func location(at index: String.Index) -> SourceLocation {
        var lo = 0
        var hi = lineStarts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if lineStarts[mid] <= index {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        let line = max(0, lo - 1)
        let lineStart = lineStarts[line]
        let column = contents.distance(from: lineStart, to: index)
        let offset = contents.distance(from: contents.startIndex, to: index)
        return SourceLocation(
            line: UInt32(line + 1),
            column: UInt32(column + 1),
            offset: UInt32(offset)
        )
    }
}

// MARK: - Grammar

/// Holds the parser's mutable state (arena, location mapper) and exposes one
/// method per grammar production. Methods take `&Substring` input and either
/// throw `ParseError` or return a `NodeRef` (or other shape — see signatures).
///
/// We don't conform productions to swift-parsing's `Parser` protocol because
/// every production needs the arena, which would force per-production structs
/// to capture it. Method-on-class is simpler and reads top-to-bottom. Where
/// swift-parsing primitives compose cleanly without state, we use them.
final class Grammar {
    let arena: SyntaxArena
    let mapper: LocationMapper

    init(arena: SyntaxArena) {
        self.arena = arena
        self.mapper = LocationMapper(contents: arena.source.contents)
    }

    // MARK: Entry — module

    /// `module = package { import } { rule }`. v1-strict: rule bodies must
    /// use the `if` keyword; legacy bracket-set heads (`name[term]` without
    /// `:=` / `if`) are rejected.
    func parseModule(_ input: inout Substring) throws -> NodeRef {
        skipTrivia(&input)
        let start = input.startIndex
        let pkgRef = try parsePackage(&input)
        skipTrivia(&input)

        var imports: [NodeRef] = []
        while isKeyword("import", input) {
            imports.append(try parseImport(&input))
            skipTrivia(&input)
        }

        var rules: [NodeRef] = []
        while !input.isEmpty {
            rules.append(try parseRule(&input))
            skipTrivia(&input)
        }

        let end = input.startIndex
        let moduleRef = arena.add(
            .module(package: pkgRef, imports: imports, rules: rules),
            span: span(start..<end)
        )
        arena.setRoot(moduleRef)
        return moduleRef
    }

    // MARK: Trivia

    /// Consume whitespace and `# ...` comments. Comments are appended to the
    /// arena's `comments` sidecar in source order.
    func skipTrivia(_ input: inout Substring) {
        while let c = input.first {
            if c.isWhitespace {
                input.removeFirst()
            } else if c == "#" {
                consumeComment(&input)
            } else {
                break
            }
        }
    }

    /// Consume a single `# ...\n` comment. The leading `#` must be the next
    /// character. The trailing newline is *not* part of the comment span.
    private func consumeComment(_ input: inout Substring) {
        let start = input.startIndex
        // Eat through end of line.
        while let c = input.first, c != "\n" {
            input.removeFirst()
        }
        let end = input.startIndex
        let text = String(input.base[start..<end])
        arena.appendComment(Comment(span: span(start..<end), text: text))
    }

    // MARK: Package

    /// `package = "package" ref`
    func parsePackage(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        try expectKeyword("package", &input)
        skipTrivia(&input)
        let pathRef = try parseRef(&input)
        let end = input.startIndex
        return arena.add(.packageDecl(path: pathRef), span: span(start..<end))
    }

    // MARK: Refs

    /// Phase 1 ref grammar: `var { "." ident }`. Bracket args, expression-call
    /// heads, and composite-literal heads land in later phases.
    func parseRef(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        let headRef = try parseVariable(&input)
        var args: [NodeRef] = []

        while input.first == "." {
            let argStart = input.startIndex
            input.removeFirst()  // consume '.'
            let (idx, _) = try parseIdentifier(&input, allowReserved: true)
            let argEnd = input.startIndex
            let argRef = arena.add(.refArgDot(idx), span: span(argStart..<argEnd))
            args.append(argRef)
        }

        let end = input.startIndex
        return arena.add(.ref(head: headRef, args: args), span: span(start..<end))
    }

    /// `var = ( ALPHA | "_" ) { ALPHA | DIGIT | "_" }` and not a reserved word.
    /// Carve-out: `data` and `input` look like reserved words but are valid
    /// ref heads — they refer to the root data and input documents. Other
    /// reserved words (`if`, `package`, …) cannot bind as variables.
    func parseVariable(_ input: inout Substring) throws -> NodeRef {
        let (idx, identSpan) = try parseIdentifier(&input, allowReserved: true)
        let text = arena.string(idx)
        if reservedWords.contains(text), text != "data", text != "input" {
            throw ParseError(
                kind: .reservedWord(text),
                span: identSpan,
                message: "`\(text)` is a reserved word and cannot be used as a variable"
            )
        }
        return arena.add(.variable(idx), span: identSpan)
    }

    // MARK: Identifiers + keywords

    /// Bare ASCII identifier. When `allowReserved` is false, reserved words
    /// (e.g. `if`, `package`) raise a `ParseError`.
    ///
    /// In ref-arg position (`.foo`) reserved words are accepted as field
    /// names — the upstream parser does the same, since `data.input` is a
    /// valid path even though `input` is a reserved word.
    func parseIdentifier(
        _ input: inout Substring,
        allowReserved: Bool
    ) throws -> (StringPool.Index, SourceSpan) {
        let start = input.startIndex
        guard let first = input.first, isIdentStart(first) else {
            throw ParseError(
                kind: .expected("identifier"),
                span: span(start..<start),
                message: "expected identifier"
            )
        }
        input.removeFirst()
        while let c = input.first, isIdentCont(c) {
            input.removeFirst()
        }
        let end = input.startIndex
        let text = String(input.base[start..<end])
        if !allowReserved, reservedWords.contains(text) {
            throw ParseError(
                kind: .reservedWord(text),
                span: span(start..<end),
                message: "`\(text)` is a reserved word and cannot be used as an identifier"
            )
        }
        return (arena.intern(text), span(start..<end))
    }

    /// Match an exact keyword followed by a non-identifier-continuation
    /// character (or EOF). `package` matches `package`, but not `packaged`.
    func expectKeyword(_ keyword: String, _ input: inout Substring) throws {
        let start = input.startIndex
        guard input.starts(with: keyword) else {
            throw ParseError(
                kind: .expected("`\(keyword)`"),
                span: span(start..<start),
                message: "expected `\(keyword)`"
            )
        }
        let afterKeyword = input.index(start, offsetBy: keyword.count)
        if afterKeyword < input.endIndex {
            let next = input.base[afterKeyword]
            if isIdentCont(next) {
                throw ParseError(
                    kind: .expected("`\(keyword)`"),
                    span: span(start..<start),
                    message: "expected `\(keyword)`"
                )
            }
        }
        input = input[afterKeyword...]
    }

    // MARK: Character classes

    private func isIdentStart(_ c: Character) -> Bool {
        guard c.isASCII else { return false }
        return c.isLetter || c == "_"
    }

    private func isIdentCont(_ c: Character) -> Bool {
        guard c.isASCII else { return false }
        return c.isLetter || c.isNumber || c == "_"
    }

    private func isDigit(_ c: Character) -> Bool {
        guard c.isASCII else { return false }
        return c.isNumber
    }

    private func isHexDigit(_ c: Character) -> Bool {
        guard c.isASCII else { return false }
        return c.isHexDigit
    }

    // MARK: Phase 2 — Scalars

    /// `scalar = string | NUMBER | TRUE | FALSE | NULL`
    /// Dispatches on the first character.
    func parseScalar(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        guard let first = input.first else {
            throw ParseError(
                kind: .expected("scalar"),
                span: span(start..<start),
                message: "expected scalar"
            )
        }
        switch first {
        case "\"":
            return try parseDoubleQuotedString(&input)
        case "`":
            return try parseRawString(&input)
        case "$":
            return try parseTemplateString(&input)
        case "-":
            return try parseNumber(&input)
        default:
            break
        }
        if isDigit(first) {
            return try parseNumber(&input)
        }
        // true / false / null are the remaining scalar literals. Each must
        // not be followed by an identifier-continuation character (so e.g.
        // `truthy_var` doesn't accidentally match).
        if tryConsumeKeyword("true", &input) {
            let end = input.startIndex
            return arena.add(.scalarBool(true), span: span(start..<end))
        }
        if tryConsumeKeyword("false", &input) {
            let end = input.startIndex
            return arena.add(.scalarBool(false), span: span(start..<end))
        }
        if tryConsumeKeyword("null", &input) {
            let end = input.startIndex
            return arena.add(.scalarNull, span: span(start..<end))
        }
        throw ParseError(
            kind: .expected("scalar"),
            span: span(start..<start),
            message: "expected scalar"
        )
    }

    // MARK: Phase 2 — Strings (double-quoted)

    /// JSON-style double-quoted string with escapes:
    /// `\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`, `\uXXXX` (surrogate
    /// pairs supported). Raw control characters (< 0x20) are rejected.
    func parseDoubleQuotedString(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        precondition(input.first == "\"", "parseDoubleQuotedString called without leading quote")
        input.removeFirst()

        var decoded = ""
        while let c = input.first {
            switch c {
            case "\"":
                input.removeFirst()
                let end = input.startIndex
                return arena.add(
                    .scalarString(arena.intern(decoded)),
                    span: span(start..<end)
                )
            case "\\":
                let escapeStart = input.startIndex
                input.removeFirst()
                try decoded.append(parseEscapeSequence(&input, openedAt: escapeStart, allowCurlyEscape: false))
            default:
                if isControlCharacter(c) {
                    let here = input.startIndex
                    throw ParseError(
                        kind: .invalidString("control character"),
                        span: span(here..<input.index(after: here)),
                        message: "control character must be escaped in a string"
                    )
                }
                decoded.append(c)
                input.removeFirst()
            }
        }
        throw ParseError(
            kind: .unterminatedString,
            span: span(start..<input.startIndex),
            message: "unterminated string"
        )
    }

    // MARK: Phase 2 — Strings (raw)

    /// Backtick-delimited raw string. No escapes. Multi-line allowed.
    func parseRawString(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        precondition(input.first == "`", "parseRawString called without leading backtick")
        input.removeFirst()
        let bodyStart = input.startIndex
        while let c = input.first, c != "`" {
            input.removeFirst()
        }
        guard input.first == "`" else {
            throw ParseError(
                kind: .unterminatedRawString,
                span: span(start..<input.startIndex),
                message: "unterminated raw string"
            )
        }
        let bodyEnd = input.startIndex
        input.removeFirst()  // closing backtick
        let end = input.startIndex
        let body = String(input.base[bodyStart..<bodyEnd])
        return arena.add(
            .scalarRawString(arena.intern(body)),
            span: span(start..<end)
        )
    }

    // MARK: Phase 2 — Strings (template)

    /// `$"..."` or `` $`...` ``. Splits into alternating `templateLiteral`
    /// and `templateExpr` nodes. The expression inside `{ … }` is parsed
    /// directly into a real `expr` (Phase 4); the placeholder Node carries
    /// a `NodeRef` to that expression.
    func parseTemplateString(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        precondition(input.first == "$", "parseTemplateString called without leading $")
        input.removeFirst()  // consume `$`
        guard let body = input.first, body == "\"" || body == "`" else {
            throw ParseError(
                kind: .invalidString("$"),
                span: span(start..<input.startIndex),
                message: "expected `\"` or `` ` `` after `$`"
            )
        }
        let isRaw = (body == "`")
        let delimiter: Character = body
        input.removeFirst()  // consume delimiter

        var parts: [NodeRef] = []
        var literal = ""
        var literalStart = input.startIndex

        func flushLiteral(endingAt end: String.Index) {
            guard !literal.isEmpty else { return }
            let lit = arena.add(
                .templateLiteral(arena.intern(literal)),
                span: span(literalStart..<end)
            )
            parts.append(lit)
            literal = ""
        }

        while let c = input.first {
            if c == delimiter {
                let endLiteral = input.startIndex
                flushLiteral(endingAt: endLiteral)
                input.removeFirst()  // closing delimiter
                let end = input.startIndex
                return arena.add(
                    .templateString(parts: parts, isRaw: isRaw),
                    span: span(start..<end)
                )
            }
            if c == "\\" {
                let escapeStart = input.startIndex
                input.removeFirst()
                if isRaw {
                    // Raw templates only recognise `\{`; everything else is
                    // verbatim (including the leading backslash).
                    if input.first == "{" {
                        literal.append("{")
                        input.removeFirst()
                    } else {
                        literal.append("\\")
                    }
                } else {
                    try literal.append(parseEscapeSequence(&input, openedAt: escapeStart, allowCurlyEscape: true))
                }
                continue
            }
            if c == "{" {
                let exprStart = input.startIndex
                flushLiteral(endingAt: exprStart)
                input.removeFirst()  // consume `{`
                skipTrivia(&input)
                // Template expressions allow with-modifiers
                // (`$"foo {x with input as 1}"`), so parse a literal — not
                // a bare expression — as the inner content.
                let exprRef = try parseLiteral(&input)
                skipTrivia(&input)
                guard input.first == "}" else {
                    let here = input.startIndex
                    throw ParseError(
                        kind: .expected("`}`"),
                        span: span(here..<here),
                        message: "expected `}` to close template expression"
                    )
                }
                input.removeFirst()  // consume `}`
                let exprEnd = input.startIndex
                let exprNode = arena.add(.templateExpr(exprRef), span: span(exprStart..<exprEnd))
                parts.append(exprNode)
                literalStart = input.startIndex
                continue
            }
            if !isRaw, isControlCharacter(c) {
                let here = input.startIndex
                throw ParseError(
                    kind: .invalidString("control character"),
                    span: span(here..<input.index(after: here)),
                    message: "control character must be escaped in a template string"
                )
            }
            literal.append(c)
            input.removeFirst()
        }
        throw ParseError(
            kind: .unterminatedString,
            span: span(start..<input.startIndex),
            message: "unterminated template string"
        )
    }

    // MARK: Phase 2 — Numbers

    /// JSON-format number: `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE][+-]? [0-9]+)?`
    /// Stored as raw text via the string pool so callers can parse to the
    /// numeric type they want without lossy normalisation.
    func parseNumber(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex

        if input.first == "-" {
            input.removeFirst()
        }

        // Integer portion.
        guard let firstDigit = input.first, isDigit(firstDigit) else {
            throw ParseError(
                kind: .invalidNumber(String(input.base[start..<input.startIndex])),
                span: span(start..<input.startIndex),
                message: "expected digit"
            )
        }
        if firstDigit == "0" {
            input.removeFirst()
            // Leading zeros are not allowed: `00`, `01`, etc. The next char
            // (if any) must not be a digit.
            if let next = input.first, isDigit(next) {
                throw ParseError(
                    kind: .invalidNumber(String(input.base[start..<input.startIndex])),
                    span: span(start..<input.startIndex),
                    message: "leading zeros are not permitted in numbers"
                )
            }
        } else {
            while let c = input.first, isDigit(c) {
                input.removeFirst()
            }
        }

        // Fraction.
        if input.first == "." {
            input.removeFirst()
            guard let d = input.first, isDigit(d) else {
                throw ParseError(
                    kind: .invalidNumber(String(input.base[start..<input.startIndex])),
                    span: span(start..<input.startIndex),
                    message: "expected digit after `.`"
                )
            }
            while let c = input.first, isDigit(c) {
                input.removeFirst()
            }
        }

        // Exponent.
        if let e = input.first, e == "e" || e == "E" {
            input.removeFirst()
            if let sign = input.first, sign == "+" || sign == "-" {
                input.removeFirst()
            }
            guard let d = input.first, isDigit(d) else {
                throw ParseError(
                    kind: .invalidNumber(String(input.base[start..<input.startIndex])),
                    span: span(start..<input.startIndex),
                    message: "expected digit in exponent"
                )
            }
            while let c = input.first, isDigit(c) {
                input.removeFirst()
            }
        }

        let end = input.startIndex
        let raw = String(input.base[start..<end])
        return arena.add(
            .scalarNumber(arena.intern(raw)),
            span: span(start..<end)
        )
    }

    // MARK: Phase 3 — Terms (dispatcher)

    /// `term = ref | var | scalar | array | object | set | …`
    ///
    /// `parseTerm` parses a base term (`parseTermBase`) and then attaches
    /// any number of suffixes that turn it into a richer ref/call structure:
    ///   `.name`        — dot ref-arg
    ///   `[expr]`       — bracket ref-arg (Phase 4)
    ///   `(args)`       — function call (Phase 4)
    ///
    /// Comprehensions (`[t | q]`, `{t | q}`, `{k: v | q}`) need expressions
    /// and queries; they're deferred to phase 5 and currently raise
    /// `unsupportedSyntax`.
    func parseTerm(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        var current = try parseTermBase(&input)
        while true {
            switch input.first {
            case ".":
                current = try attachDotArg(to: current, baseStart: start, &input)
            case "[":
                current = try attachBracketArg(to: current, baseStart: start, &input)
            case "(":
                current = try attachCall(to: current, baseStart: start, &input)
            default:
                return current
            }
        }
    }

    /// Bare term with no ref-args / call attached. Internal helper for
    /// `parseTerm`.
    private func parseTermBase(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        guard let first = input.first else {
            throw ParseError(
                kind: .expected("term"),
                span: span(start..<start),
                message: "expected term"
            )
        }

        switch first {
        case "\"", "`", "$", "-":
            return try parseScalar(&input)
        case "[":
            return try parseArray(&input)
        case "{":
            return try parseObjectOrSet(&input)
        default:
            break
        }

        if isDigit(first) {
            return try parseScalar(&input)
        }

        guard isIdentStart(first) else {
            throw ParseError(
                kind: .expected("term"),
                span: span(start..<start),
                message: "expected term"
            )
        }

        if let keywordScalar = tryParseScalarKeyword(&input) {
            return keywordScalar
        }
        if let emptySet = tryParseEmptySet(&input) {
            return emptySet
        }
        // Reserved words like `else`, `if`, `with` are not bare-expression
        // values, but per the v1 grammar they may appear as ref atoms — e.g.
        // `else.foo == 3`. Accept them as variable heads when followed by
        // `.` or `[` so the suffix loop can fold the path. Bare uses still
        // fall through to `parseVariable` which rejects them.
        if let varRef = tryParseReservedAsRefHead(&input) {
            return varRef
        }
        return try parseVariable(&input)
    }

    /// If `input` starts with a reserved-word identifier (other than the
    /// always-allowed `data` / `input` / scalar keywords) AND it is
    /// followed by `.` or `[`, consume it and return a `variable` node.
    /// Otherwise return `nil` and leave `input` untouched.
    private func tryParseReservedAsRefHead(_ input: inout Substring) -> NodeRef? {
        var probe = input
        let identStart = probe.startIndex
        guard let first = probe.first, isIdentStart(first) else { return nil }
        while let c = probe.first, isIdentCont(c) {
            probe.removeFirst()
        }
        let identEnd = probe.startIndex
        let text = String(probe.base[identStart..<identEnd])
        guard reservedWords.contains(text), text != "data", text != "input" else { return nil }
        let next = probe.first
        guard next == "." || next == "[" else { return nil }
        input = probe
        let idx = arena.intern(text)
        return arena.add(.variable(idx), span: span(identStart..<identEnd))
    }

    private func attachDotArg(
        to current: NodeRef,
        baseStart: String.Index,
        _ input: inout Substring
    ) throws -> NodeRef {
        let argStart = input.startIndex
        input.removeFirst()  // consume `.`
        let (idx, _) = try parseIdentifier(&input, allowReserved: true)
        let argEnd = input.startIndex
        let argRef = arena.add(.refArgDot(idx), span: span(argStart..<argEnd))
        return appendRefArg(to: current, arg: argRef, baseStart: baseStart, end: argEnd)
    }

    private func attachBracketArg(
        to current: NodeRef,
        baseStart: String.Index,
        _ input: inout Substring
    ) throws -> NodeRef {
        let argStart = input.startIndex
        input.removeFirst()  // consume `[`
        skipTrivia(&input)
        let exprRef = try parseExpr(&input)
        skipTrivia(&input)
        guard input.first == "]" else {
            let here = input.startIndex
            throw ParseError(
                kind: .expected("`]`"),
                span: span(here..<here),
                message: "expected `]` after bracket reference argument"
            )
        }
        input.removeFirst()
        let argEnd = input.startIndex
        let argRef = arena.add(.refArgBracket(exprRef), span: span(argStart..<argEnd))
        return appendRefArg(to: current, arg: argRef, baseStart: baseStart, end: argEnd)
    }

    private func attachCall(
        to current: NodeRef,
        baseStart: String.Index,
        _ input: inout Substring
    ) throws -> NodeRef {
        input.removeFirst()  // consume `(`
        skipTrivia(&input)
        var args: [NodeRef] = []
        if input.first != ")" {
            args.append(try parseExpr(&input))
            skipTrivia(&input)
            while input.first == "," {
                input.removeFirst()
                skipTrivia(&input)
                if input.first == ")" { break }
                args.append(try parseExpr(&input))
                skipTrivia(&input)
            }
        }
        guard input.first == ")" else {
            let here = input.startIndex
            throw ParseError(
                kind: .expected("`)`"),
                span: span(here..<here),
                message: "expected `)` after call arguments"
            )
        }
        input.removeFirst()
        let end = input.startIndex
        return arena.add(.call(callee: current, args: args), span: span(baseStart..<end))
    }

    /// Either extend an existing `.ref` node's args list or wrap a non-ref
    /// base in a new `.ref` node carrying its first arg.
    private func appendRefArg(
        to current: NodeRef,
        arg: NodeRef,
        baseStart: String.Index,
        end: String.Index
    ) -> NodeRef {
        if case .ref(let head, var args) = arena.node(at: current) {
            args.append(arg)
            return arena.add(.ref(head: head, args: args), span: span(baseStart..<end))
        }
        return arena.add(.ref(head: current, args: [arg]), span: span(baseStart..<end))
    }

    // MARK: Phase 3 — Composites

    /// `array = "[" [ term { "," term } ] "]"` (trailing commas tolerated).
    /// `array-compr = "[" term "|" query "]"`.
    func parseArray(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        precondition(input.first == "[", "parseArray called without leading `[`")
        input.removeFirst()
        skipTrivia(&input)

        if input.first == "]" {
            input.removeFirst()
            return arena.add(.array(elements: []), span: span(start..<input.startIndex))
        }

        let firstElement = try parseExpr(&input, allowPipe: false)
        skipTrivia(&input)

        if input.first == "|" {
            input.removeFirst()
            skipTrivia(&input)
            let body = try parseQuery(&input)
            skipTrivia(&input)
            guard input.first == "]" else {
                let here = input.startIndex
                throw ParseError(
                    kind: .expected("`]`"),
                    span: span(here..<here),
                    message: "expected `]` to close array comprehension"
                )
            }
            input.removeFirst()
            return arena.add(
                .arrayCompr(term: firstElement, body: body),
                span: span(start..<input.startIndex)
            )
        }

        var elements = [firstElement]
        while input.first == "," {
            input.removeFirst()
            skipTrivia(&input)
            if input.first == "]" { break }
            elements.append(try parseExpr(&input))
            skipTrivia(&input)
        }
        guard input.first == "]" else {
            let here = input.startIndex
            throw ParseError(
                kind: .expected("`]` or `,`"),
                span: span(here..<here),
                message: "expected `]` or `,` in array literal"
            )
        }
        input.removeFirst()
        return arena.add(.array(elements: elements), span: span(start..<input.startIndex))
    }

    /// `{ … }` disambiguating between object literal, set literal, and
    /// empty `{}` (always an object). Set/object comprehensions branch off
    /// at the first `|`.
    func parseObjectOrSet(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        precondition(input.first == "{", "parseObjectOrSet called without leading `{`")
        input.removeFirst()
        skipTrivia(&input)

        if input.first == "}" {
            input.removeFirst()
            return arena.add(.object(pairs: []), span: span(start..<input.startIndex))
        }

        let firstTerm = try parseExpr(&input, allowPipe: false)
        skipTrivia(&input)

        switch input.first {
        case ":":
            return try finishObject(start: start, firstKey: firstTerm, &input)
        case "|":
            return try finishSetCompr(start: start, term: firstTerm, &input)
        default:
            return try finishSet(start: start, firstElement: firstTerm, &input)
        }
    }

    private func finishSetCompr(
        start: String.Index,
        term: NodeRef,
        _ input: inout Substring
    ) throws -> NodeRef {
        precondition(input.first == "|", "finishSetCompr called without `|`")
        input.removeFirst()
        skipTrivia(&input)
        let body = try parseQuery(&input)
        skipTrivia(&input)
        guard input.first == "}" else {
            let here = input.startIndex
            throw ParseError(
                kind: .expected("`}`"),
                span: span(here..<here),
                message: "expected `}` to close set comprehension"
            )
        }
        input.removeFirst()
        return arena.add(.setCompr(term: term, body: body), span: span(start..<input.startIndex))
    }

    /// Continue parsing an object literal after the first key has been read
    /// and a `:` is the next character. If the post-value separator is `|`,
    /// switch to object-comprehension parsing.
    private func finishObject(
        start: String.Index,
        firstKey: NodeRef,
        _ input: inout Substring
    ) throws -> NodeRef {
        precondition(input.first == ":", "finishObject called without `:`")
        input.removeFirst()
        skipTrivia(&input)
        let firstValue = try parseExpr(&input, allowPipe: false)
        skipTrivia(&input)

        if input.first == "|" {
            input.removeFirst()
            skipTrivia(&input)
            let body = try parseQuery(&input)
            skipTrivia(&input)
            guard input.first == "}" else {
                let here = input.startIndex
                throw ParseError(
                    kind: .expected("`}`"),
                    span: span(here..<here),
                    message: "expected `}` to close object comprehension"
                )
            }
            input.removeFirst()
            return arena.add(
                .objectCompr(key: firstKey, value: firstValue, body: body),
                span: span(start..<input.startIndex)
            )
        }

        let firstPair = makePair(key: firstKey, value: firstValue)
        var pairs = [firstPair]
        while input.first == "," {
            input.removeFirst()
            skipTrivia(&input)
            if input.first == "}" { break }
            let key = try parseExpr(&input)
            skipTrivia(&input)
            guard input.first == ":" else {
                let here = input.startIndex
                throw ParseError(
                    kind: .expected("`:`"),
                    span: span(here..<here),
                    message: "expected `:` in object literal"
                )
            }
            input.removeFirst()
            skipTrivia(&input)
            let value = try parseExpr(&input)
            pairs.append(makePair(key: key, value: value))
            skipTrivia(&input)
        }
        guard input.first == "}" else {
            let here = input.startIndex
            throw ParseError(
                kind: .expected("`}` or `,`"),
                span: span(here..<here),
                message: "expected `}` or `,` in object literal"
            )
        }
        input.removeFirst()
        return arena.add(.object(pairs: pairs), span: span(start..<input.startIndex))
    }

    /// Continue parsing a set literal after the first element has been read
    /// and the next character is `,` or `}`.
    private func finishSet(
        start: String.Index,
        firstElement: NodeRef,
        _ input: inout Substring
    ) throws -> NodeRef {
        var elements = [firstElement]
        while input.first == "," {
            input.removeFirst()
            skipTrivia(&input)
            if input.first == "}" { break }
            elements.append(try parseExpr(&input))
            skipTrivia(&input)
        }
        guard input.first == "}" else {
            let here = input.startIndex
            throw ParseError(
                kind: .expected("`}` or `,`"),
                span: span(here..<here),
                message: "expected `}` or `,` in set literal"
            )
        }
        input.removeFirst()
        return arena.add(.set(elements: elements), span: span(start..<input.startIndex))
    }

    private func makePair(key: NodeRef, value: NodeRef) -> NodeRef {
        let pairSpan = SourceSpan.union(arena.span(of: key), arena.span(of: value))
        return arena.add(.kvPair(key: key, value: value), span: pairSpan)
    }

    /// `true` / `false` / `null` keyword scalars. Returns nil if the input
    /// doesn't start with one followed by a non-identifier-cont character.
    private func tryParseScalarKeyword(_ input: inout Substring) -> NodeRef? {
        let start = input.startIndex
        if tryConsumeKeyword("true", &input) {
            return arena.add(.scalarBool(true), span: span(start..<input.startIndex))
        }
        if tryConsumeKeyword("false", &input) {
            return arena.add(.scalarBool(false), span: span(start..<input.startIndex))
        }
        if tryConsumeKeyword("null", &input) {
            return arena.add(.scalarNull, span: span(start..<input.startIndex))
        }
        return nil
    }

    /// `set()` empty-set literal. Whitespace is allowed between `(` and
    /// `)`, but `set` and `(` must be adjacent — that's the disambiguator
    /// against a function call `set(x)`. Returns nil if the input doesn't
    /// match.
    private func tryParseEmptySet(_ input: inout Substring) -> NodeRef? {
        let start = input.startIndex
        guard input.starts(with: "set(") else { return nil }
        let afterParen = input.index(start, offsetBy: 4)
        var probe = input[afterParen...]
        while let c = probe.first, c.isWhitespace { probe.removeFirst() }
        guard probe.first == ")" else { return nil }
        probe.removeFirst()
        let end = probe.startIndex
        input = probe
        return arena.add(.set(elements: []), span: span(start..<end))
    }

    // MARK: Phase 4 — Expressions
    //
    // Precedence stack (lowest → highest):
    //   parseExpr → parseLogicalOr → parseLogicalAnd → parseInfix
    //     → parseUnary → parsePrimary → parseTerm
    //
    // Infix precedence levels (higher = tighter binding):
    //   10  := =
    //   30  == != < <= > >= in
    //   35  |
    //   40  &
    //   50  + -
    //   60  * / %

    /// Parse a full expression. The grammar's `expr` lumps everything
    /// together; here we split the work across helper levels for clarity
    /// and so logical/infix/unary/primary each handle their own concern.
    ///
    /// `allowPipe` controls whether `|` (set union / "binary or") is
    /// treated as an infix operator. It must be `false` when parsing the
    /// first element / key / value of an array, object, or set literal,
    /// because there `|` is the comprehension separator. Subsequent
    /// elements (post-`,`) and the comprehension body can use the default.
    ///
    /// `allowComma` enables the comma-form membership term:
    ///     `key , value in domain` → `Node.membership(key, value, domain)`.
    /// It is opt-in because the grammar uses `,` as both element separator
    /// (in arrays / sets / objects) and membership-pair joiner. Callers in
    /// parens (`(...)`) and at literal-body top level pass `true`; element
    /// positions pass `false`.
    func parseExpr(
        _ input: inout Substring,
        allowPipe: Bool = true,
        allowComma: Bool = false
    ) throws -> NodeRef {
        let lhs = try parseLogicalOr(&input, allowPipe: allowPipe)
        guard allowComma else { return lhs }
        return try maybeAttachCommaMembership(lhs: lhs, allowPipe: allowPipe, &input)
    }

    /// If the current input position has `, expr in expr`, fold it into a
    /// `Node.membership(key: lhs, value: …, domain: …)`. Otherwise return
    /// `lhs` and leave `input` unchanged.
    ///
    /// `parseLogicalOr` greedily consumes `value in domain` as a single
    /// `.binary(.in, value, domain)` node — so rather than parse `value`
    /// and `domain` separately (which would require a "no-`in`" mode), we
    /// parse one expression and pattern-match the result.
    private func maybeAttachCommaMembership(
        lhs: NodeRef,
        allowPipe: Bool,
        _ input: inout Substring
    ) throws -> NodeRef {
        let saved = input
        skipTrivia(&input)
        guard input.first == "," else {
            input = saved
            return lhs
        }
        var probe = input
        probe.removeFirst()  // consume `,`
        skipTrivia(&probe)
        let parsed: NodeRef
        do {
            parsed = try parseLogicalOr(&probe, allowPipe: allowPipe)
        } catch {
            input = saved
            return lhs
        }
        // Accept only when the parsed RHS is exactly `value in domain`.
        // Anything else (`a + b`, a logical chain, etc.) means the comma
        // belongs to the surrounding context, so we restore.
        guard case .binary(.in, let value, let domain) = arena.node(at: parsed) else {
            input = saved
            return lhs
        }
        input = probe
        let s = SourceSpan.union(arena.span(of: lhs), arena.span(of: domain))
        return arena.add(.membership(key: lhs, value: value, domain: domain), span: s)
    }

    private func parseLogicalOr(_ input: inout Substring, allowPipe: Bool) throws -> NodeRef {
        let start = input.startIndex
        var left = try parseLogicalAnd(&input, allowPipe: allowPipe)
        while true {
            let savedInput = input
            skipTrivia(&input)
            guard tryConsumeKeyword("or", &input) else {
                input = savedInput
                break
            }
            skipTrivia(&input)
            let right = try parseLogicalAnd(&input, allowPipe: allowPipe)
            let end = input.startIndex
            left = arena.add(.logical(op: .or, lhs: left, rhs: right), span: span(start..<end))
        }
        return left
    }

    private func parseLogicalAnd(_ input: inout Substring, allowPipe: Bool) throws -> NodeRef {
        let start = input.startIndex
        var left = try parseInfix(&input, minPrec: 0, allowPipe: allowPipe)
        while true {
            let savedInput = input
            skipTrivia(&input)
            guard tryConsumeKeyword("and", &input) else {
                input = savedInput
                break
            }
            skipTrivia(&input)
            let right = try parseInfix(&input, minPrec: 0, allowPipe: allowPipe)
            let end = input.startIndex
            left = arena.add(.logical(op: .and, lhs: left, rhs: right), span: span(start..<end))
        }
        return left
    }

    /// Precedence-climbing parser for infix binary operators. Operators are
    /// left-associative.
    private func parseInfix(_ input: inout Substring, minPrec: Int, allowPipe: Bool) throws -> NodeRef {
        let start = input.startIndex
        var left = try parseUnary(&input)
        while true {
            let savedInput = input
            skipTrivia(&input)
            guard let match = peekInfixOp(input, allowPipe: allowPipe) else {
                input = savedInput
                break
            }
            if match.prec < minPrec {
                input = savedInput
                break
            }
            // Consume the operator's lexical span.
            input = input.dropFirst(match.length)
            skipTrivia(&input)
            // Operands deeper than this operator can use `|` freely; only
            // the *outermost* expression call needs `allowPipe == false`.
            let right = try parseInfix(&input, minPrec: match.prec + 1, allowPipe: true)
            let end = input.startIndex
            left = arena.add(.binary(op: match.op, lhs: left, rhs: right), span: span(start..<end))
        }
        return left
    }

    private func parseUnary(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        if input.first == "-" {
            // The grammar restricts unary minus to numbers and refs.
            // Numbers are handled by parseScalar (signed-number form), so
            // here we only handle the ref form. If the `-` is followed by a
            // digit, defer to `parseTerm`; otherwise treat as unary minus
            // applied to a primary expression.
            let next = input.index(after: input.startIndex)
            if next < input.endIndex {
                let c = input.base[next]
                if isDigit(c) {
                    return try parseTerm(&input)
                }
                if isIdentStart(c) || c == "(" {
                    input.removeFirst()  // consume `-`
                    skipTrivia(&input)
                    let operand = try parseUnary(&input)
                    let end = input.startIndex
                    return arena.add(.unary(op: .minus, operand: operand), span: span(start..<end))
                }
            }
        }
        return try parsePrimary(&input)
    }

    private func parsePrimary(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex

        if input.first == "(" {
            input.removeFirst()
            skipTrivia(&input)
            let inner = try parseExpr(&input, allowComma: true)
            skipTrivia(&input)
            guard input.first == ")" else {
                let here = input.startIndex
                throw ParseError(
                    kind: .expected("`)`"),
                    span: span(here..<here),
                    message: "expected `)` to close parenthesised expression"
                )
            }
            input.removeFirst()
            let end = input.startIndex
            return arena.add(.parens(inner), span: span(start..<end))
        }

        if isKeyword("every", input) {
            input = input.dropFirst("every".count)
            return try parseEvery(start: start, &input)
        }

        return try parseTerm(&input)
    }

    /// Look at `input` (without consuming) and report whether it starts with
    /// an infix operator, which one, and how many characters it spans.
    /// Multi-character operators are checked before their prefixes. The
    /// `in` keyword is matched here too, with a non-identifier-cont guard.
    /// `|` is only considered when `allowPipe` is `true`.
    private func peekInfixOp(_ input: Substring, allowPipe: Bool = true) -> (op: BinOp, prec: Int, length: Int)? {
        if input.starts(with: "==") { return (.eq, 30, 2) }
        if input.starts(with: "!=") { return (.ne, 30, 2) }
        if input.starts(with: "<=") { return (.le, 30, 2) }
        if input.starts(with: ">=") { return (.ge, 30, 2) }
        if input.starts(with: ":=") { return (.assign, 10, 2) }
        if input.starts(with: "<") { return (.lt, 30, 1) }
        if input.starts(with: ">") { return (.gt, 30, 1) }
        if input.starts(with: "=") { return (.unify, 10, 1) }
        if input.starts(with: "+") { return (.add, 50, 1) }
        if input.starts(with: "-") { return (.sub, 50, 1) }
        if input.starts(with: "*") { return (.mul, 60, 1) }
        if input.starts(with: "/") { return (.div, 60, 1) }
        if input.starts(with: "%") { return (.mod, 60, 1) }
        if allowPipe, input.starts(with: "|") { return (.bitOr, 35, 1) }
        if input.starts(with: "&") { return (.bitAnd, 40, 1) }
        if isKeyword("in", input) { return (.in, 30, 2) }
        return nil
    }

    /// Returns true if `input` starts with `keyword` and the next character
    /// (if any) is not an identifier-continuation character. Does *not*
    /// consume input.
    private func matchesKeyword(_ keyword: String, _ input: Substring) -> Bool {
        guard input.starts(with: keyword) else { return false }
        let after = input.index(input.startIndex, offsetBy: keyword.count, limitedBy: input.endIndex)
        guard let after else { return true }
        if after >= input.endIndex { return true }
        return !isIdentCont(input.base[after])
    }

    /// True if `input` starts with `keyword` AS a keyword usage — that is,
    /// followed by a non-identifier-continuation character that is also
    /// NOT `.` or `[`. The latter exclusion is important because reserved
    /// words may appear as ref atoms (`else.foo`, `with.bar`), and those
    /// should not be consumed as keywords.
    private func isKeyword(_ keyword: String, _ input: Substring) -> Bool {
        guard matchesKeyword(keyword, input) else { return false }
        let after = input.index(input.startIndex, offsetBy: keyword.count, limitedBy: input.endIndex)
        guard let after, after < input.endIndex else { return true }
        let next = input.base[after]
        return next != "." && next != "["
    }

    // MARK: Phase 5 — Queries and literals

    /// `query = literal { ( ";" | LF ) literal }`
    /// Parses a sequence of literals separated by `;` or newlines and stops
    /// on a closing delimiter (`}`, `]`, `)`) or EOF. The trailing
    /// delimiter is *not* consumed — the caller is responsible for that.
    func parseQuery(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        skipTrivia(&input)
        guard canStartLiteral(input) else {
            // Empty query.
            return arena.add(.query(literals: []), span: span(start..<input.startIndex))
        }
        var literals = [try parseLiteral(&input)]
        while true {
            let saved = input
            // After a literal, look for a separator: `;` or newline. Inline
            // trivia (spaces/tabs/comments-on-this-line) doesn't count as a
            // separator on its own.
            skipInlineTrivia(&input)
            if input.first == ";" {
                input.removeFirst()
                skipTrivia(&input)
                if !canStartLiteral(input) { break }
                literals.append(try parseLiteral(&input))
                continue
            }
            if let c = input.first, isNewline(c) {
                skipTrivia(&input)
                if !canStartLiteral(input) { break }
                literals.append(try parseLiteral(&input))
                continue
            }
            // No separator → query is done. Restore so the caller sees the
            // post-literal whitespace state untouched.
            input = saved
            break
        }
        return arena.add(.query(literals: literals), span: span(start..<input.startIndex))
    }

    /// `literal = ( some-decl | expr | "not" ( expr | "{" query "}" ) ) { with-modifier }`
    func parseLiteral(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        let body: NodeRef
        if isKeyword("some", input) {
            input = input.dropFirst("some".count)
            skipTrivia(&input)
            body = try parseSomeDecl(start: start, &input)
        } else if isKeyword("not", input) {
            input = input.dropFirst("not".count)
            skipTrivia(&input)
            body = try parseNotLiteral(start: start, &input)
        } else {
            // Top-level literal expressions allow comma-form membership
            // (`"foo", x in {…}`) — bare comma-pairs only make sense at
            // statement level.
            body = try parseExpr(&input, allowComma: true)
        }

        var modifiers: [NodeRef] = []
        while true {
            let saved = input
            // `with` modifiers may continue across newlines:
            //
            //     data.foo with input.a as 1
            //         with input.b as 2
            //
            // We use full trivia here (not inline-only) so a continuation
            // is recognised. If the next token isn't `with`, we restore
            // `input` so any consumed newlines remain visible to the outer
            // query as the literal-separator they are.
            //
            // Use `isKeyword` so `with.foo`-style refs aren't mistaken for
            // a modifier introducer.
            skipTrivia(&input)
            guard isKeyword("with", input) else {
                input = saved
                break
            }
            modifiers.append(try parseWithModifier(&input))
        }

        if modifiers.isEmpty {
            return body
        }
        return arena.add(
            .literal(body: body, withModifiers: modifiers),
            span: span(start..<input.startIndex)
        )
    }

    /// `some-decl = "some" term [ "," term ] "in" expr | "some" var { "," var }`.
    ///
    /// The `in`-form supports any term on the LHS — including composite
    /// patterns (`some {"foo": x} in arr`) and ground values (`some "foo"
    /// in arr`). The bare-vars form (no `in`) is restricted to variable
    /// identifiers; if the parsed list contains a non-variable term we
    /// reject because `some` without `in` only declares names.
    private func parseSomeDecl(start: String.Index, _ input: inout Substring) throws -> NodeRef {
        var terms = [try parseTerm(&input)]
        while true {
            let saved = input
            skipTrivia(&input)
            guard input.first == "," else {
                input = saved
                break
            }
            input.removeFirst()
            skipTrivia(&input)
            // Don't speculatively parse on EOF or close-delim — a stray
            // trailing comma would otherwise burn through orphan nodes.
            guard let c = input.first, !isCloseDelim(c) else {
                input = saved
                break
            }
            terms.append(try parseTerm(&input))
        }

        let saved = input
        skipTrivia(&input)
        if isKeyword("in", input) {
            input = input.dropFirst("in".count)
            skipTrivia(&input)
            let domain = try parseExpr(&input)
            guard terms.count <= 2 else {
                throw ParseError(
                    kind: .other("too many terms before `in` in some-decl"),
                    span: span(start..<input.startIndex),
                    message: "`some … in` accepts at most two terms (key, value)"
                )
            }
            let key: NodeRef? = terms.count == 2 ? terms[0] : nil
            guard let value = terms.last else {
                throw ParseError(
                    kind: .expected("term"),
                    span: span(start..<input.startIndex),
                    message: "expected term in `some … in` declaration"
                )
            }
            return arena.add(
                .someIn(key: key, value: value, domain: domain),
                span: span(start..<input.startIndex)
            )
        }
        input = saved
        // Bare-vars form — every term must be a plain variable.
        var vars: [NodeRef] = []
        for t in terms {
            guard case .variable = arena.node(at: t) else {
                throw ParseError(
                    kind: .expected("variable"),
                    span: arena.span(of: t),
                    message: "`some` without `in` may only declare variables"
                )
            }
            vars.append(t)
        }
        return arena.add(.someDecl(vars: vars), span: span(start..<input.startIndex))
    }

    private func isCloseDelim(_ c: Character) -> Bool {
        c == "}" || c == "]" || c == ")"
    }

    private func parseNotLiteral(start: String.Index, _ input: inout Substring) throws -> NodeRef {
        if input.first == "{" {
            input.removeFirst()
            skipTrivia(&input)
            let query = try parseQuery(&input)
            skipTrivia(&input)
            guard input.first == "}" else {
                let here = input.startIndex
                throw ParseError(
                    kind: .expected("`}`"),
                    span: span(here..<here),
                    message: "expected `}` to close query block"
                )
            }
            input.removeFirst()
            return arena.add(.notLiteral(target: query), span: span(start..<input.startIndex))
        }
        let target = try parseExpr(&input)
        return arena.add(.notLiteral(target: target), span: span(start..<input.startIndex))
    }

    private func parseWithModifier(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        precondition(matchesKeyword("with", input), "parseWithModifier called without `with`")
        input = input.dropFirst("with".count)
        skipTrivia(&input)
        let target = try parseTerm(&input)
        skipTrivia(&input)
        guard isKeyword("as", input) else {
            let here = input.startIndex
            throw ParseError(
                kind: .expected("`as`"),
                span: span(here..<here),
                message: "expected `as` in `with` modifier"
            )
        }
        input = input.dropFirst("as".count)
        skipTrivia(&input)
        let value = try parseTerm(&input)
        return arena.add(
            .withModifier(target: target, value: value),
            span: span(start..<input.startIndex)
        )
    }

    /// `every var [, var] in expr { query }`. The `every` keyword is
    /// consumed by the caller (`parsePrimary`).
    func parseEvery(start: String.Index, _ input: inout Substring) throws -> NodeRef {
        skipTrivia(&input)
        let firstVar = try parseVariable(&input)
        skipTrivia(&input)
        var key: NodeRef?
        var value: NodeRef = firstVar
        if input.first == "," {
            input.removeFirst()
            skipTrivia(&input)
            let secondVar = try parseVariable(&input)
            key = firstVar
            value = secondVar
            skipTrivia(&input)
        }
        guard isKeyword("in", input) else {
            let here = input.startIndex
            throw ParseError(
                kind: .expected("`in`"),
                span: span(here..<here),
                message: "expected `in` in `every` quantifier"
            )
        }
        input = input.dropFirst("in".count)
        skipTrivia(&input)
        let domain = try parseExpr(&input)
        skipTrivia(&input)
        guard input.first == "{" else {
            let here = input.startIndex
            throw ParseError(
                kind: .expected("`{`"),
                span: span(here..<here),
                message: "expected `{` to begin `every` body"
            )
        }
        input.removeFirst()
        skipTrivia(&input)
        let body = try parseQuery(&input)
        skipTrivia(&input)
        guard input.first == "}" else {
            let here = input.startIndex
            throw ParseError(
                kind: .expected("`}`"),
                span: span(here..<here),
                message: "expected `}` to close `every` body"
            )
        }
        input.removeFirst()
        return arena.add(
            .every(key: key, value: value, domain: domain, body: body),
            span: span(start..<input.startIndex)
        )
    }

    /// True if the next character could plausibly start a literal. Used by
    /// `parseQuery` to decide whether to continue after a separator. We're
    /// liberal: `parseLiteral` will throw a precise error if the candidate
    /// doesn't actually parse.
    private func canStartLiteral(_ input: Substring) -> Bool {
        guard let c = input.first else { return false }
        if c == "}" || c == "]" || c == ")" { return false }
        return true
    }

    /// Whitespace + same-line `# …` comments only — does NOT consume `\n`
    /// or `\r`. Used at query separator positions so newlines remain
    /// detectable as statement terminators.
    private func skipInlineTrivia(_ input: inout Substring) {
        while let c = input.first {
            if c == " " || c == "\t" {
                input.removeFirst()
            } else if c == "#" {
                consumeComment(&input)
                // `consumeComment` stops at the newline; do not consume it.
                return
            } else {
                return
            }
        }
    }

    private func isNewline(_ c: Character) -> Bool {
        c == "\n" || c == "\r"
    }

    // MARK: Phase 2 — Lexical helpers

    /// Try to match an exact keyword followed by a non-identifier-cont
    /// character (or EOF). Consumes on success, leaves `input` untouched
    /// on failure.
    private func tryConsumeKeyword(_ keyword: String, _ input: inout Substring) -> Bool {
        guard input.starts(with: keyword) else { return false }
        let after = input.index(input.startIndex, offsetBy: keyword.count)
        if after < input.endIndex, isIdentCont(input.base[after]) {
            return false
        }
        input = input[after...]
        return true
    }

    /// Decode a `\X` escape that begins immediately after the backslash has
    /// been consumed. If `allowCurlyEscape` is true, `\{` decodes to `{`
    /// (used inside non-raw template strings).
    private func parseEscapeSequence(
        _ input: inout Substring,
        openedAt escapeStart: String.Index,
        allowCurlyEscape: Bool
    ) throws -> Character {
        guard let escape = input.first else {
            throw ParseError(
                kind: .unterminatedString,
                span: span(escapeStart..<input.startIndex),
                message: "unterminated escape sequence"
            )
        }
        switch escape {
        case "\"":
            input.removeFirst()
            return "\""
        case "\\":
            input.removeFirst()
            return "\\"
        case "/":
            input.removeFirst()
            return "/"
        case "b":
            input.removeFirst()
            return "\u{08}"
        case "f":
            input.removeFirst()
            return "\u{0C}"
        case "n":
            input.removeFirst()
            return "\n"
        case "r":
            input.removeFirst()
            return "\r"
        case "t":
            input.removeFirst()
            return "\t"
        case "u":
            input.removeFirst()
            return try parseUnicodeEscape(&input, openedAt: escapeStart)
        case "{":
            guard allowCurlyEscape else {
                throw ParseError(
                    kind: .invalidString("\\{"),
                    span: span(escapeStart..<input.index(after: input.startIndex)),
                    message: "invalid escape sequence `\\{`"
                )
            }
            input.removeFirst()
            return "{"
        default:
            let badEnd = input.index(after: input.startIndex)
            throw ParseError(
                kind: .invalidString("\\\(escape)"),
                span: span(escapeStart..<badEnd),
                message: "invalid escape sequence `\\\(escape)`"
            )
        }
    }

    /// `\uXXXX` (4 hex digits). Handles UTF-16 surrogate pairs by requiring
    /// a second `\uXXXX` immediately after a high surrogate.
    private func parseUnicodeEscape(
        _ input: inout Substring,
        openedAt escapeStart: String.Index
    ) throws -> Character {
        let hex1 = try parseHex4(&input, openedAt: escapeStart)
        if (0xD800...0xDBFF).contains(hex1) {
            // High surrogate — expect the matching low surrogate.
            guard input.starts(with: "\\u") else {
                throw ParseError(
                    kind: .invalidString("\\u\(String(hex1, radix: 16))"),
                    span: span(escapeStart..<input.startIndex),
                    message: "expected low surrogate after high surrogate"
                )
            }
            input.removeFirst(2)
            let hex2 = try parseHex4(&input, openedAt: escapeStart)
            guard (0xDC00...0xDFFF).contains(hex2) else {
                throw ParseError(
                    kind: .invalidString("\\u\(String(hex2, radix: 16))"),
                    span: span(escapeStart..<input.startIndex),
                    message: "expected low surrogate after high surrogate"
                )
            }
            let codepoint = 0x10000 + ((hex1 - 0xD800) << 10) + (hex2 - 0xDC00)
            guard let scalar = UnicodeScalar(codepoint) else {
                throw ParseError(
                    kind: .invalidString("\\u"),
                    span: span(escapeStart..<input.startIndex),
                    message: "invalid Unicode scalar"
                )
            }
            return Character(scalar)
        }
        guard let scalar = UnicodeScalar(hex1) else {
            // Lone low surrogate (0xDC00..0xDFFF) lands here.
            throw ParseError(
                kind: .invalidString("\\u\(String(hex1, radix: 16))"),
                span: span(escapeStart..<input.startIndex),
                message: "invalid Unicode scalar"
            )
        }
        return Character(scalar)
    }

    /// Consume exactly four hex digits, returning the decoded value.
    private func parseHex4(_ input: inout Substring, openedAt escapeStart: String.Index) throws -> Int {
        var value = 0
        for _ in 0..<4 {
            guard let c = input.first, isHexDigit(c) else {
                throw ParseError(
                    kind: .invalidString("\\u"),
                    span: span(escapeStart..<input.startIndex),
                    message: "expected 4 hex digits after `\\u`"
                )
            }
            value = value * 16 + hexDigitValue(c)
            input.removeFirst()
        }
        return value
    }

    private func hexDigitValue(_ c: Character) -> Int {
        switch c {
        case "0"..."9": return Int(c.asciiValue! - Character("0").asciiValue!)
        case "a"..."f": return Int(c.asciiValue! - Character("a").asciiValue!) + 10
        case "A"..."F": return Int(c.asciiValue! - Character("A").asciiValue!) + 10
        default: return 0
        }
    }

    private func isControlCharacter(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        return scalar.value < 0x20
    }

    // MARK: Phase 6 — Rules

    /// `rule = [ "default" ] rule-head [ rule-body ] { else-clause }`.
    ///
    /// The `if` keyword is consumed by `parseRuleHead`, which records its
    /// presence in `hasIf` on the resulting `ruleHead` node. We use that to
    /// decide whether a body is required and whether bare `{ … }` is allowed
    /// (it isn't — v1-strict rejects body-without-`if`).
    func parseRule(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        var isDefault = false
        // `default` is only the keyword form when not followed by `.` / `[`
        // (else it's a ref head like `default.foo := 1`).
        if isKeyword("default", input) {
            _ = tryConsumeKeyword("default", &input)
            isDefault = true
            skipTrivia(&input)
        }

        let headRef = try parseRuleHead(&input)
        let headHasIf: Bool
        if case .ruleHead(_, _, _, let hasIf) = arena.node(at: headRef) {
            headHasIf = hasIf
        } else {
            headHasIf = false
        }

        var bodyRef: NodeRef?
        // Attempt to attach a body. Skip *inline* trivia so we don't eat
        // newlines that ought to terminate the previous rule.
        let bodyProbe = input
        skipTrivia(&input)
        if input.first == "{" {
            // v1-strict: braces directly after the head require `if`.
            guard headHasIf else {
                let here = input.startIndex
                throw ParseError(
                    kind: .other("rule body requires `if` keyword"),
                    span: span(here..<here),
                    message: "rule body in v1 requires the `if` keyword before `{`"
                )
            }
            // Route through parseRuleBody so a comprehension body
            // (`if {x: i | q}`) is correctly recognised.
            bodyRef = try parseRuleBody(&input)
        } else if headHasIf {
            // After `if`, the body is required: either `{ query }` or a
            // single literal.
            bodyRef = try parseRuleBody(&input)
        } else {
            // No `if`, no `{` — no body. Restore so the outer module loop
            // can re-skip trivia naturally.
            input = bodyProbe
        }

        var elseClauses: [NodeRef] = []
        while true {
            let savedInput = input
            skipTrivia(&input)
            guard isKeyword("else", input) else {
                input = savedInput
                break
            }
            elseClauses.append(try parseElseClause(&input))
        }

        let end = input.startIndex
        return arena.add(
            .rule(default: isDefault, head: headRef, body: bodyRef, elseClauses: elseClauses),
            span: span(start..<end)
        )
    }

    /// `rule-head = ( ref | var ) ( rule-head-set | rule-head-func | rule-head-comp )`.
    ///
    /// The "name" is parsed as a full ref (variable + any number of `.x` /
    /// `[expr]` arguments) — this captures both `users[id]` and
    /// `p.allow[action][resource]` etc. After consuming the name, we
    /// dispatch on what follows:
    ///   `(args)`            → function head
    ///   `contains <term>`   → set head
    ///   `:=` / `=` / `if`   → complete head with optional value/body
    ///
    /// A bare ref with no continuation token is rejected as v1-strict
    /// legacy syntax.
    private func parseRuleHead(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        let nameRef = try parseRuleHeadName(&input)

        var kind: RuleHeadKind = .complete
        let savedAfterName = input
        skipTrivia(&input)
        switch input.first {
        case "(":
            // Function-head `(args)` is only valid when the name is a bare
            // ref with no bracket args; otherwise the `(` would have been
            // consumed as a call ref-arg by `parseRuleHeadName`. Practically
            // we accept it here either way.
            kind = try parseFunctionHead(&input)
        default:
            if isKeyword("contains", input) {
                input = input.dropFirst("contains".count)
                kind = try parseSetHeadAfterContains(&input)
            } else {
                input = savedAfterName
            }
        }

        // Optional value: `:= expr` or `= expr`. We use `parseExpr` rather
        // than `parseTerm` because real-world rules write things like
        // `f(a, b) := a + b` where the value is a full expression.
        var value: NodeRef?
        let savedBeforeValue = input
        skipTrivia(&input)
        if input.starts(with: ":=") {
            input.removeFirst(2)
            skipTrivia(&input)
            value = try parseExpr(&input)
        } else if input.first == "=" && !input.starts(with: "==") {
            input.removeFirst()
            skipTrivia(&input)
            value = try parseExpr(&input)
        } else {
            input = savedBeforeValue
        }

        // Optional `if` keyword.
        var hasIf = false
        let savedBeforeIf = input
        skipTrivia(&input)
        if isKeyword("if", input) {
            input = input.dropFirst("if".count)
            hasIf = true
        } else {
            input = savedBeforeIf
        }

        // v1-strict: a bare ref head with no value, no body, no else makes
        // no sense as a rule. Reject if we matched only a name (with or
        // without brackets) and saw nothing after it. The outer parseRule
        // checks for `{` body and `else`; we only validate "complete head
        // produced something useful" here.
        if case .complete = kind, value == nil, !hasIf {
            // The ref name has bracket args? → legacy partial-set syntax.
            if case .ref(_, let args) = arena.node(at: nameRef),
                args.contains(where: { isRefBracketArg($0) })
            {
                throw ParseError(
                    kind: .other("legacy bracket-set head"),
                    span: span(start..<input.startIndex),
                    message:
                        "legacy `name[term]` partial-set syntax is rejected; use `name contains term` instead"
                )
            }
        }

        let end = input.startIndex
        return arena.add(
            .ruleHead(name: nameRef, kind: kind, value: value, hasIf: hasIf),
            span: span(start..<end)
        )
    }

    /// Helper: is `ref` a `refArgBracket` node?
    private func isRefBracketArg(_ ref: NodeRef) -> Bool {
        if case .refArgBracket = arena.node(at: ref) { return true }
        return false
    }

    /// Greedy ref consumer used at rule-head positions: variable, then any
    /// number of `.ident` (refArgDot) or `[expr]` (refArgBracket) suffixes.
    /// Function-call suffixes (`(args)`) are NOT consumed here — the caller
    /// inspects them as a possible function-head trigger.
    ///
    /// Reserved words are accepted at the head position. `null.foo := 1`
    /// and `else.foo := 1` are valid v1 because `null`/`else`/etc. are only
    /// reserved as bare expressions; in path positions they bind as ref
    /// atoms.
    private func parseRuleHeadName(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        let (idx, headSpan) = try parseIdentifier(&input, allowReserved: true)
        let head = arena.add(.variable(idx), span: headSpan)
        var args: [NodeRef] = []
        loop: while true {
            switch input.first {
            case ".":
                let argStart = input.startIndex
                input.removeFirst()  // consume `.`
                let (idx, _) = try parseIdentifier(&input, allowReserved: true)
                let argEnd = input.startIndex
                args.append(arena.add(.refArgDot(idx), span: span(argStart..<argEnd)))
            case "[":
                let argStart = input.startIndex
                input.removeFirst()  // consume `[`
                skipTrivia(&input)
                let exprRef = try parseExpr(&input)
                skipTrivia(&input)
                guard input.first == "]" else {
                    let here = input.startIndex
                    throw ParseError(
                        kind: .expected("`]`"),
                        span: span(here..<here),
                        message: "expected `]` after rule-head bracket argument"
                    )
                }
                input.removeFirst()
                let argEnd = input.startIndex
                args.append(arena.add(.refArgBracket(exprRef), span: span(argStart..<argEnd)))
            default:
                break loop
            }
        }
        let end = input.startIndex
        return arena.add(.ref(head: head, args: args), span: span(start..<end))
    }

    /// `rule-head-func = "(" rule-args ")"`. Arguments are terms per the
    /// grammar (not full expressions).
    private func parseFunctionHead(_ input: inout Substring) throws -> RuleHeadKind {
        precondition(input.first == "(", "parseFunctionHead called without `(`")
        input.removeFirst()
        skipTrivia(&input)
        var args: [NodeRef] = []
        if input.first != ")" {
            args.append(try parseTerm(&input))
            skipTrivia(&input)
            while input.first == "," {
                input.removeFirst()
                skipTrivia(&input)
                if input.first == ")" { break }
                args.append(try parseTerm(&input))
                skipTrivia(&input)
            }
        }
        guard input.first == ")" else {
            let here = input.startIndex
            throw ParseError(
                kind: .expected("`)`"),
                span: span(here..<here),
                message: "expected `)` to close function-head arguments"
            )
        }
        input.removeFirst()
        return .function(args: args)
    }

    /// `rule-head-set = "contains" term`. Caller has already consumed the
    /// `contains` keyword.
    private func parseSetHeadAfterContains(_ input: inout Substring) throws -> RuleHeadKind {
        skipTrivia(&input)
        let member = try parseTerm(&input)
        return .set(member: member)
    }

    /// `rule-body = literal | "{" query "}"`. Used after the `if` keyword.
    ///
    /// The `{` form is ambiguous: `if {x | q}` or `if {k: v | q}` should
    /// be a single-literal body whose body is a comprehension, not a
    /// brace-block query of `x | q` (which doesn't even parse). We
    /// disambiguate by speculatively parsing as a literal: if the result
    /// is a comprehension, accept it; otherwise restore and treat as a
    /// brace-query. Arena nodes from the failed branch are orphaned.
    private func parseRuleBody(_ input: inout Substring) throws -> NodeRef {
        skipTrivia(&input)
        if input.first == "{" {
            let saved = input
            if let lit = tryParseComprehensionAsBody(&input) {
                return lit
            }
            input = saved
            return try parseBraceBody(&input)
        }
        // Single-literal body — wrap in a 1-literal query for AST uniformity.
        let lit = try parseLiteral(&input)
        let litSpan = arena.span(of: lit)
        return arena.add(.query(literals: [lit]), span: litSpan)
    }

    /// Attempt to parse the upcoming `{...}` as a comprehension literal
    /// (set / object / array). Returns a 1-literal query wrapping the
    /// comprehension on success; `nil` (and restored input) otherwise.
    private func tryParseComprehensionAsBody(_ input: inout Substring) -> NodeRef? {
        let saved = input
        let lit: NodeRef
        do {
            lit = try parseLiteral(&input)
        } catch {
            input = saved
            return nil
        }
        switch arena.node(at: lit) {
        case .arrayCompr, .setCompr, .objectCompr:
            let litSpan = arena.span(of: lit)
            return arena.add(.query(literals: [lit]), span: litSpan)
        default:
            input = saved
            return nil
        }
    }

    /// `"{" query "}"`. Caller positions us on the opening brace.
    private func parseBraceBody(_ input: inout Substring) throws -> NodeRef {
        precondition(input.first == "{", "parseBraceBody called without `{`")
        input.removeFirst()
        skipTrivia(&input)
        let q = try parseQuery(&input)
        skipTrivia(&input)
        guard input.first == "}" else {
            let here = input.startIndex
            throw ParseError(
                kind: .expected("`}`"),
                span: span(here..<here),
                message: "expected `}` to close rule body"
            )
        }
        input.removeFirst()
        return q
    }

    /// `else-clause = "else" [ assign-operator term ] [ else-body ]`
    /// `else-body  = "if" ( literal | "{" query "}" ) | "{" query "}"`.
    private func parseElseClause(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        precondition(matchesKeyword("else", input), "parseElseClause called without `else`")
        input = input.dropFirst("else".count)

        var value: NodeRef?
        let savedBeforeValue = input
        skipTrivia(&input)
        if input.starts(with: ":=") {
            input.removeFirst(2)
            skipTrivia(&input)
            value = try parseTerm(&input)
        } else if input.first == "=" && !input.starts(with: "==") {
            input.removeFirst()
            skipTrivia(&input)
            value = try parseTerm(&input)
        } else {
            input = savedBeforeValue
        }

        var body: NodeRef?
        let savedBeforeBody = input
        skipTrivia(&input)
        if isKeyword("if", input) {
            input = input.dropFirst("if".count)
            body = try parseRuleBody(&input)
        } else if input.first == "{" {
            body = try parseBraceBody(&input)
        } else {
            input = savedBeforeBody
        }

        let end = input.startIndex
        return arena.add(.elseClause(value: value, body: body), span: span(start..<end))
    }

    // MARK: Phase 7 — Imports

    /// `import = "import" ref [ "as" var ]`.
    func parseImport(_ input: inout Substring) throws -> NodeRef {
        let start = input.startIndex
        try expectKeyword("import", &input)
        skipTrivia(&input)
        let pathRef = try parseRef(&input)

        var alias: StringPool.Index?
        let savedBeforeAs = input
        skipTrivia(&input)
        if isKeyword("as", input) {
            input = input.dropFirst("as".count)
            skipTrivia(&input)
            let (idx, _) = try parseIdentifier(&input, allowReserved: false)
            alias = idx
        } else {
            input = savedBeforeAs
        }

        let end = input.startIndex
        return arena.add(.importDecl(path: pathRef, alias: alias), span: span(start..<end))
    }

    // MARK: Span helper

    func span(_ range: Range<String.Index>) -> SourceSpan {
        SourceSpan(
            start: mapper.location(at: range.lowerBound),
            end: mapper.location(at: range.upperBound)
        )
    }
}
