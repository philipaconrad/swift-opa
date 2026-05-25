//
//  QueryTests.swift
//  Phase 5 — queries, literals, with-mods, some, not, every, comprehensions.
//

import Foundation
import Testing

@testable import Parser

@Suite
struct ParserPhase5QueryTests {
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

    // MARK: parseQuery — separators

    @Test
    func parsesSingleLiteralQuery() throws {
        let f = Fixture("x == 1")
        let ref = try f.grammar.parseQuery(&f.input)
        guard case .query(let lits) = f.arena.node(at: ref), lits.count == 1 else {
            Issue.record("expected single-literal query")
            return
        }
    }

    @Test
    func parsesSemicolonSeparatedLiterals() throws {
        let f = Fixture("x == 1; y == 2; z == 3")
        let ref = try f.grammar.parseQuery(&f.input)
        guard case .query(let lits) = f.arena.node(at: ref), lits.count == 3 else {
            Issue.record("expected 3 literals")
            return
        }
    }

    @Test
    func parsesNewlineSeparatedLiterals() throws {
        let f = Fixture("x == 1\ny == 2\nz == 3")
        let ref = try f.grammar.parseQuery(&f.input)
        guard case .query(let lits) = f.arena.node(at: ref), lits.count == 3 else {
            Issue.record("expected 3 literals")
            return
        }
    }

    @Test
    func parsesMixedSeparators() throws {
        let f = Fixture("a; b\nc")
        let ref = try f.grammar.parseQuery(&f.input)
        guard case .query(let lits) = f.arena.node(at: ref), lits.count == 3 else {
            Issue.record("expected 3 literals")
            return
        }
    }

    @Test
    func emptyQueryStopsAtClosingDelimiter() throws {
        var input: Substring = "}"
        let f = Fixture("}")
        f.input = input
        let ref = try f.grammar.parseQuery(&f.input)
        guard case .query(let lits) = f.arena.node(at: ref), lits.isEmpty else {
            Issue.record("expected empty query")
            return
        }
        // Caller is responsible for `}`; query parser leaves it.
        #expect(f.input == "}")
        _ = input  // silence
    }

    // MARK: with-modifiers

    @Test
    func parsesSingleWithModifier() throws {
        let f = Fixture(#"allow with input as {"x": 1}"#)
        let ref = try f.grammar.parseLiteral(&f.input)
        guard case .literal(_, let mods) = f.arena.node(at: ref), mods.count == 1 else {
            Issue.record("expected literal with one with-modifier")
            return
        }
        guard case .withModifier = f.arena.node(at: mods[0]) else {
            Issue.record("expected withModifier")
            return
        }
    }

    @Test
    func parsesMultipleWithModifiers() throws {
        let f = Fixture("allow with input as a with data.role as b")
        let ref = try f.grammar.parseLiteral(&f.input)
        guard case .literal(_, let mods) = f.arena.node(at: ref), mods.count == 2 else {
            Issue.record("expected 2 with-modifiers")
            return
        }
    }

    @Test
    func bareLiteralReturnsBodyDirectly() throws {
        // No with-mods → result is the body NodeRef, not a `.literal` wrapper.
        let f = Fixture("x == 1")
        let ref = try f.grammar.parseLiteral(&f.input)
        guard case .binary(.eq, _, _) = f.arena.node(at: ref) else {
            Issue.record("expected binary `==` directly")
            return
        }
    }

    @Test
    func withMissingAsErrors() {
        let f = Fixture("allow with input")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseLiteral(&f.input)
        }
    }

    // MARK: some-decl

    @Test
    func parsesSomeWithIn() throws {
        let f = Fixture("some x in xs")
        let ref = try f.grammar.parseLiteral(&f.input)
        guard case .someIn(let key, _, _) = f.arena.node(at: ref) else {
            Issue.record("expected someIn")
            return
        }
        #expect(key == nil)
    }

    @Test
    func parsesSomeKeyValueIn() throws {
        let f = Fixture("some k, v in xs")
        let ref = try f.grammar.parseLiteral(&f.input)
        guard case .someIn(let key, _, _) = f.arena.node(at: ref), key != nil else {
            Issue.record("expected someIn with key")
            return
        }
    }

    @Test
    func parsesSomeMultipleVars() throws {
        // `some a, b, c` — declaration form, no `in`.
        let f = Fixture("some a, b, c")
        let ref = try f.grammar.parseLiteral(&f.input)
        guard case .someDecl(let vars) = f.arena.node(at: ref), vars.count == 3 else {
            Issue.record("expected someDecl with 3 vars")
            return
        }
    }

    @Test
    func someInWithThreeVarsIsAnError() {
        // `some a, b, c in xs` — too many vars before `in`.
        let f = Fixture("some a, b, c in xs")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseLiteral(&f.input)
        }
    }

    // MARK: not

    @Test
    func parsesNotExpr() throws {
        let f = Fixture("not x == 1")
        let ref = try f.grammar.parseLiteral(&f.input)
        guard case .notLiteral(let target) = f.arena.node(at: ref),
            case .binary(.eq, _, _) = f.arena.node(at: target)
        else {
            Issue.record("expected notLiteral wrapping binary")
            return
        }
    }

    @Test
    func parsesNotQueryBlock() throws {
        let f = Fixture("not { a; b }")
        let ref = try f.grammar.parseLiteral(&f.input)
        guard case .notLiteral(let target) = f.arena.node(at: ref),
            case .query(let lits) = f.arena.node(at: target),
            lits.count == 2
        else {
            Issue.record("expected notLiteral wrapping 2-literal query")
            return
        }
    }

    // MARK: every

    @Test
    func parsesEveryWithIn() throws {
        let f = Fixture("every x in xs { x > 0 }")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .every(let key, _, _, let body) = f.arena.node(at: ref),
            key == nil,
            case .query = f.arena.node(at: body)
        else {
            Issue.record("expected every with query body")
            return
        }
    }

    @Test
    func parsesEveryKeyValue() throws {
        let f = Fixture("every k, v in xs { v > k }")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .every(let key, _, _, _) = f.arena.node(at: ref), key != nil else {
            Issue.record("expected every with key")
            return
        }
    }

    @Test
    func everyMissingInErrors() {
        let f = Fixture("every x { x > 0 }")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseExpr(&f.input)
        }
    }

    @Test
    func everyMissingBodyErrors() {
        let f = Fixture("every x in xs")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseExpr(&f.input)
        }
    }

    // MARK: Comprehensions reach via parseTerm/parseExpr

    @Test
    func arrayComprBodyIsAQuery() throws {
        let f = Fixture("[x*2 | some x in xs; x > 0]")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .arrayCompr(_, let body) = f.arena.node(at: ref),
            case .query(let lits) = f.arena.node(at: body),
            lits.count == 2
        else {
            Issue.record("expected arrayCompr with 2-literal body")
            return
        }
    }

    @Test
    func setComprBodyIsAQuery() throws {
        let f = Fixture("{x | x in xs}")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .setCompr = f.arena.node(at: ref) else {
            Issue.record("expected setCompr")
            return
        }
    }

    @Test
    func objectComprBodyIsAQuery() throws {
        let f = Fixture(#"{k: v | some k, v in xs}"#)
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .objectCompr = f.arena.node(at: ref) else {
            Issue.record("expected objectCompr")
            return
        }
    }

    // MARK: Embedded queries pick up comments

    @Test
    func commentsInsideQueryRecorded() throws {
        let f = Fixture("[x |\n    # filter\n    x > 0\n]")
        _ = try f.grammar.parseTerm(&f.input)
        #expect(f.arena.comments.count == 1)
        #expect(f.arena.comments[0].text == "# filter")
    }
}
