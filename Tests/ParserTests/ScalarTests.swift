//
//  ScalarTests.swift
//  Phase 2 — direct tests for Grammar.parseScalar et al. via @testable.
//

import Foundation
import Testing

@testable import Parser

@Suite
struct ParserPhase2ScalarTests {
    private final class Fixture {
        let arena: SyntaxArena
        let grammar: Grammar
        var input: Substring

        init(_ contents: String) {
            let source = SourceFile(
                url: URL(fileURLWithPath: "test.rego"),
                bundleID: nil,
                contents: contents
            )
            self.arena = SyntaxArena(source: source)
            self.grammar = Grammar(arena: arena)
            self.input = Substring(contents)
        }
    }

    // MARK: Bool / null

    @Test
    func parsesTrue() throws {
        let f = Fixture("true")
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .scalarBool(true) = f.arena.node(at: ref) else {
            Issue.record("expected scalarBool(true), got \(f.arena.node(at: ref))")
            return
        }
        #expect(f.input.isEmpty)
    }

    @Test
    func parsesFalse() throws {
        let f = Fixture("false")
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .scalarBool(false) = f.arena.node(at: ref) else {
            Issue.record("expected scalarBool(false)")
            return
        }
    }

    @Test
    func parsesNull() throws {
        let f = Fixture("null")
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .scalarNull = f.arena.node(at: ref) else {
            Issue.record("expected scalarNull")
            return
        }
    }

    @Test
    func keywordPrefixIsNotABool() {
        let f = Fixture("true_value")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseScalar(&f.input)
        }
    }

    // MARK: Numbers

    @Test
    func parsesIntegers() throws {
        for raw in ["0", "42", "-1", "-0"] {
            let f = Fixture(raw)
            let ref = try f.grammar.parseScalar(&f.input)
            guard case .scalarNumber(let idx) = f.arena.node(at: ref) else {
                Issue.record("\(raw): expected scalarNumber")
                continue
            }
            #expect(f.arena.string(idx) == raw)
        }
    }

    @Test
    func parsesFloatsAndExponents() throws {
        for raw in ["3.14", "1e10", "1.5e-3", "0.5", "-2.5E+10"] {
            let f = Fixture(raw)
            let ref = try f.grammar.parseScalar(&f.input)
            guard case .scalarNumber(let idx) = f.arena.node(at: ref) else {
                Issue.record("\(raw): expected scalarNumber")
                continue
            }
            #expect(f.arena.string(idx) == raw)
        }
    }

    @Test
    func rejectsLeadingZeros() {
        let f = Fixture("0123")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseScalar(&f.input)
        }
    }

    @Test
    func rejectsBareDot() {
        let f = Fixture("3.")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseScalar(&f.input)
        }
    }

    @Test
    func rejectsDanglingExponent() {
        let f = Fixture("3e")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseScalar(&f.input)
        }
    }

    // MARK: Double-quoted strings

    @Test
    func parsesEmptyString() throws {
        let f = Fixture("\"\"")
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .scalarString(let idx) = f.arena.node(at: ref) else {
            Issue.record("expected scalarString")
            return
        }
        #expect(f.arena.string(idx) == "")
    }

    @Test
    func parsesPlainString() throws {
        let f = Fixture("\"hello world\"")
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .scalarString(let idx) = f.arena.node(at: ref) else {
            Issue.record("expected scalarString")
            return
        }
        #expect(f.arena.string(idx) == "hello world")
    }

    @Test
    func parsesSimpleEscapes() throws {
        let f = Fixture(#""a\nb\tc\"d\\e\/f""#)
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .scalarString(let idx) = f.arena.node(at: ref) else {
            Issue.record("expected scalarString")
            return
        }
        #expect(f.arena.string(idx) == "a\nb\tc\"d\\e/f")
    }

    @Test
    func parsesUnicodeEscape() throws {
        let f = Fixture(#""é""#)
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .scalarString(let idx) = f.arena.node(at: ref) else {
            Issue.record("expected scalarString")
            return
        }
        #expect(f.arena.string(idx) == "é")
    }

    @Test
    func parsesSurrogatePair() throws {
        // U+1F600 (😀) encoded as a UTF-16 surrogate pair.
        let f = Fixture(#""😀""#)
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .scalarString(let idx) = f.arena.node(at: ref) else {
            Issue.record("expected scalarString")
            return
        }
        #expect(f.arena.string(idx) == "😀")
    }

    @Test
    func rejectsLoneHighSurrogate() {
        let f = Fixture(#""\uD83D""#)
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseScalar(&f.input)
        }
    }

    @Test
    func rejectsBadEscape() {
        let f = Fixture(#""\q""#)
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseScalar(&f.input)
        }
    }

    @Test
    func rejectsUnterminatedString() {
        let f = Fixture("\"oops")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseScalar(&f.input)
        }
    }

    @Test
    func rejectsControlCharacter() {
        let f = Fixture("\"a\nb\"")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseScalar(&f.input)
        }
    }

    // MARK: Raw strings

    @Test
    func parsesRawString() throws {
        let f = Fixture("`hello\\nworld`")
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .scalarRawString(let idx) = f.arena.node(at: ref) else {
            Issue.record("expected scalarRawString")
            return
        }
        // Backslash + n is preserved verbatim in raw strings.
        #expect(f.arena.string(idx) == "hello\\nworld")
    }

    @Test
    func parsesMultiLineRawString() throws {
        let f = Fixture("`line1\nline2`")
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .scalarRawString(let idx) = f.arena.node(at: ref) else {
            Issue.record("expected scalarRawString")
            return
        }
        #expect(f.arena.string(idx) == "line1\nline2")
    }

    @Test
    func rejectsUnterminatedRawString() {
        let f = Fixture("`oops")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseScalar(&f.input)
        }
    }

    // MARK: Template strings

    @Test
    func parsesEmptyTemplateString() throws {
        let f = Fixture(#"$"""#)
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .templateString(let parts, let isRaw) = f.arena.node(at: ref) else {
            Issue.record("expected templateString")
            return
        }
        #expect(parts.isEmpty)
        #expect(isRaw == false)
    }

    @Test
    func parsesTemplateLiteralOnly() throws {
        let f = Fixture(#"$"hello""#)
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .templateString(let parts, let isRaw) = f.arena.node(at: ref),
            parts.count == 1,
            case .templateLiteral(let idx) = f.arena.node(at: parts[0])
        else {
            Issue.record("expected single literal templateString")
            return
        }
        #expect(f.arena.string(idx) == "hello")
        #expect(isRaw == false)
    }

    @Test
    func parsesTemplateWithExpr() throws {
        let f = Fixture(#"$"hi {name}!""#)
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .templateString(let parts, _) = f.arena.node(at: ref),
            parts.count == 3
        else {
            Issue.record("expected 3 parts")
            return
        }
        guard case .templateLiteral(let pre) = f.arena.node(at: parts[0]) else {
            Issue.record("expected literal")
            return
        }
        guard case .templateExpr(let exprRef) = f.arena.node(at: parts[1]) else {
            Issue.record("expected expr")
            return
        }
        guard case .templateLiteral(let post) = f.arena.node(at: parts[2]) else {
            Issue.record("expected trailing literal")
            return
        }
        #expect(f.arena.string(pre) == "hi ")
        guard case .variable(let nameIdx) = f.arena.node(at: exprRef) else {
            Issue.record("expected variable inside template expr")
            return
        }
        #expect(f.arena.string(nameIdx) == "name")
        #expect(f.arena.string(post) == "!")
    }

    @Test
    func parsesTemplateWithCurlyEscape() throws {
        let f = Fixture(#"$"\{ literal""#)
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .templateString(let parts, _) = f.arena.node(at: ref),
            parts.count == 1,
            case .templateLiteral(let idx) = f.arena.node(at: parts[0])
        else {
            Issue.record("expected single literal")
            return
        }
        #expect(f.arena.string(idx) == "{ literal")
    }

    @Test
    func parsesRawTemplateString() throws {
        let f = Fixture("$`hi \\{ {x}`")
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .templateString(let parts, let isRaw) = f.arena.node(at: ref) else {
            Issue.record("expected templateString")
            return
        }
        #expect(isRaw == true)
        #expect(parts.count == 2)
        guard case .templateLiteral(let lit) = f.arena.node(at: parts[0]),
            case .templateExpr(let exprRef) = f.arena.node(at: parts[1])
        else {
            Issue.record("unexpected parts shape")
            return
        }
        #expect(f.arena.string(lit) == "hi { ")
        guard case .variable(let xIdx) = f.arena.node(at: exprRef) else {
            Issue.record("expected variable inside expr")
            return
        }
        #expect(f.arena.string(xIdx) == "x")
    }

    @Test
    func rawTemplateDoesNotInterpretBackslashEscapes() throws {
        let f = Fixture("$`hi\\nworld`")
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .templateString(let parts, true) = f.arena.node(at: ref),
            parts.count == 1,
            case .templateLiteral(let idx) = f.arena.node(at: parts[0])
        else {
            Issue.record("expected raw template literal")
            return
        }
        // `\n` inside a raw template string is a literal backslash + n.
        #expect(f.arena.string(idx) == "hi\\nworld")
    }

    @Test
    func templateExprBalancesNestedBraces() throws {
        // Template-expr now parses to a real expression: `{a: 1}` is the
        // object literal `{a: 1}`.
        let f = Fixture(#"$"{ {a: 1} }""#)
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .templateString(let parts, _) = f.arena.node(at: ref),
            parts.count == 1,
            case .templateExpr(let exprRef) = f.arena.node(at: parts[0])
        else {
            Issue.record("expected single expr")
            return
        }
        guard case .object(let pairs) = f.arena.node(at: exprRef), pairs.count == 1 else {
            Issue.record("expected object inside template expr")
            return
        }
    }

    @Test
    func templateExprAllowsStringWithBraces() throws {
        // Template-expr containing a string literal that contains `}`.
        let f = Fixture(#"$"{ "}" }""#)
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .templateString(let parts, _) = f.arena.node(at: ref),
            parts.count == 1,
            case .templateExpr(let exprRef) = f.arena.node(at: parts[0])
        else {
            Issue.record("expected single expr")
            return
        }
        guard case .scalarString(let strIdx) = f.arena.node(at: exprRef) else {
            Issue.record("expected string literal inside template expr")
            return
        }
        #expect(f.arena.string(strIdx) == "}")
    }

    @Test
    func rejectsUnterminatedTemplateString() {
        let f = Fixture(#"$"hi"#)
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseScalar(&f.input)
        }
    }

    @Test
    func rejectsTemplateWithoutDelimiter() {
        let f = Fixture("$x")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseScalar(&f.input)
        }
    }
}
