//
//  TermTests.swift
//  Phase 3 — composite-term tests for Grammar.parseTerm.
//

import Foundation
import Testing

@testable import Parser

@Suite
struct ParserPhase3TermTests {
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

    // MARK: Dispatcher delegates to scalar / ref

    @Test
    func dispatchesScalars() throws {
        let cases: [(String, (Node) -> Bool)] = [
            (
                "42",
                {
                    if case .scalarNumber = $0 { return true }
                    return false
                }
            ),
            (
                "\"hi\"",
                {
                    if case .scalarString = $0 { return true }
                    return false
                }
            ),
            (
                "`raw`",
                {
                    if case .scalarRawString = $0 { return true }
                    return false
                }
            ),
            (
                "true",
                {
                    if case .scalarBool(true) = $0 { return true }
                    return false
                }
            ),
            (
                "false",
                {
                    if case .scalarBool(false) = $0 { return true }
                    return false
                }
            ),
            (
                "null",
                {
                    if case .scalarNull = $0 { return true }
                    return false
                }
            ),
        ]
        for (input, predicate) in cases {
            let f = Fixture(input)
            let ref = try f.grammar.parseTerm(&f.input)
            #expect(predicate(f.arena.node(at: ref)), "input \(input) should match")
        }
    }

    @Test
    func dispatchesRef() throws {
        let f = Fixture("data.foo.bar")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .ref(let head, let args) = f.arena.node(at: ref) else {
            Issue.record("expected ref")
            return
        }
        guard case .variable(let nameIdx) = f.arena.node(at: head) else {
            Issue.record("expected variable head")
            return
        }
        #expect(f.arena.string(nameIdx) == "data")
        #expect(args.count == 2)
    }

    // MARK: Arrays

    @Test
    func parsesEmptyArray() throws {
        let f = Fixture("[]")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .array(let elements) = f.arena.node(at: ref) else {
            Issue.record("expected array")
            return
        }
        #expect(elements.isEmpty)
    }

    @Test
    func parsesArrayOfMixedScalars() throws {
        let f = Fixture(#"[1, "two", true, null]"#)
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .array(let elements) = f.arena.node(at: ref) else {
            Issue.record("expected array")
            return
        }
        #expect(elements.count == 4)
        guard case .scalarNumber = f.arena.node(at: elements[0]),
            case .scalarString = f.arena.node(at: elements[1]),
            case .scalarBool(true) = f.arena.node(at: elements[2]),
            case .scalarNull = f.arena.node(at: elements[3])
        else {
            Issue.record("element types do not match")
            return
        }
    }

    @Test
    func parsesNestedArray() throws {
        let f = Fixture("[[1, 2], [3, 4]]")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .array(let outer) = f.arena.node(at: ref), outer.count == 2 else {
            Issue.record("expected outer array of 2")
            return
        }
        for inner in outer {
            guard case .array(let elements) = f.arena.node(at: inner), elements.count == 2 else {
                Issue.record("expected inner array of 2")
                return
            }
        }
    }

    @Test
    func parsesArrayWithTrailingComma() throws {
        let f = Fixture("[1, 2, 3,]")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .array(let elements) = f.arena.node(at: ref), elements.count == 3 else {
            Issue.record("expected array of 3")
            return
        }
    }

    @Test
    func parsesArrayWithWhitespace() throws {
        let f = Fixture("[\n    1,\n    # comment\n    2,\n]")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .array(let elements) = f.arena.node(at: ref), elements.count == 2 else {
            Issue.record("expected array of 2")
            return
        }
        // Comment inside the array should still land in the arena.
        #expect(f.arena.comments.count == 1)
    }

    @Test
    func parsesArrayComprehension() throws {
        let f = Fixture("[x | x = 1]")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .arrayCompr(let term, let body) = f.arena.node(at: ref),
            case .variable = f.arena.node(at: term),
            case .query(let lits) = f.arena.node(at: body),
            lits.count == 1
        else {
            Issue.record("expected arrayCompr with one-literal body")
            return
        }
    }

    @Test
    func unterminatedArray() {
        let f = Fixture("[1, 2")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseTerm(&f.input)
        }
    }

    // MARK: Objects

    @Test
    func parsesEmptyBracesAsObject() throws {
        let f = Fixture("{}")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .object(let pairs) = f.arena.node(at: ref) else {
            Issue.record("expected empty object")
            return
        }
        #expect(pairs.isEmpty)
    }

    @Test
    func parsesObjectWithStringKeys() throws {
        let f = Fixture(#"{"a": 1, "b": 2}"#)
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .object(let pairs) = f.arena.node(at: ref), pairs.count == 2 else {
            Issue.record("expected object of 2")
            return
        }
        for pairRef in pairs {
            guard case .kvPair(let key, _) = f.arena.node(at: pairRef),
                case .scalarString = f.arena.node(at: key)
            else {
                Issue.record("expected string-keyed kvPair")
                return
            }
        }
    }

    @Test
    func parsesObjectWithMixedKeyTypes() throws {
        // Rego allows non-string keys; values are terms too.
        let f = Fixture(#"{1: "one", true: "yes", "k": null}"#)
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .object(let pairs) = f.arena.node(at: ref), pairs.count == 3 else {
            Issue.record("expected 3 pairs")
            return
        }
    }

    @Test
    func parsesNestedObject() throws {
        let f = Fixture(#"{"outer": {"inner": 42}}"#)
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .object(let pairs) = f.arena.node(at: ref), pairs.count == 1 else {
            Issue.record("expected outer object")
            return
        }
        guard case .kvPair(_, let valueRef) = f.arena.node(at: pairs[0]),
            case .object = f.arena.node(at: valueRef)
        else {
            Issue.record("expected nested object as value")
            return
        }
    }

    @Test
    func parsesObjectWithTrailingComma() throws {
        let f = Fixture(#"{"a": 1, "b": 2,}"#)
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .object(let pairs) = f.arena.node(at: ref), pairs.count == 2 else {
            Issue.record("expected object of 2")
            return
        }
    }

    @Test
    func parsesObjectComprehension() throws {
        let f = Fixture(#"{"a": v | v = 1}"#)
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .objectCompr(_, _, let body) = f.arena.node(at: ref),
            case .query = f.arena.node(at: body)
        else {
            Issue.record("expected objectCompr")
            return
        }
    }

    @Test
    func objectMissingColon() {
        let f = Fixture(#"{"a": 1, "b" 2}"#)
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseTerm(&f.input)
        }
    }

    // MARK: Sets

    @Test
    func parsesEmptySetSyntax() throws {
        let f = Fixture("set()")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .set(let elements) = f.arena.node(at: ref) else {
            Issue.record("expected set")
            return
        }
        #expect(elements.isEmpty)
    }

    @Test
    func parsesEmptySetWithInternalWhitespace() throws {
        let f = Fixture("set(   )")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .set(let elements) = f.arena.node(at: ref), elements.isEmpty else {
            Issue.record("expected empty set")
            return
        }
    }

    @Test
    func setOfElementsParsesAsSet() throws {
        let f = Fixture(#"{1, 2, "three"}"#)
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .set(let elements) = f.arena.node(at: ref), elements.count == 3 else {
            Issue.record("expected set of 3")
            return
        }
    }

    @Test
    func setWithTrailingComma() throws {
        let f = Fixture("{1, 2, 3,}")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .set(let elements) = f.arena.node(at: ref), elements.count == 3 else {
            Issue.record("expected set of 3")
            return
        }
    }

    @Test
    func parsesSetComprehension() throws {
        let f = Fixture("{x | x = 1}")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .setCompr(_, let body) = f.arena.node(at: ref),
            case .query = f.arena.node(at: body)
        else {
            Issue.record("expected setCompr")
            return
        }
    }

    @Test
    func setIdentifierAsRefIfNotEmptySet() throws {
        // `set` is not a reserved word; without a trailing `(...)` it
        // should parse as a normal variable / ref head.
        let f = Fixture("set.foo")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .ref(let head, let args) = f.arena.node(at: ref),
            case .variable(let idx) = f.arena.node(at: head)
        else {
            Issue.record("expected ref with `set` head")
            return
        }
        #expect(f.arena.string(idx) == "set")
        #expect(args.count == 1)
    }

    @Test
    func emptySetSyntaxRequiresAdjacentParen() throws {
        // `set ()` (whitespace between `set` and `(`) is *not* the empty-set
        // syntax — that requires `set(` adjacent. The whitespace also
        // prevents the `(` from being attached as a function call (the
        // call-attach loop in `parseTerm` does not skip trivia between the
        // callee and `(`). So we get a bare `set` variable and leave ` ()`
        // unconsumed.
        let f = Fixture("set ()")
        let ref = try f.grammar.parseTerm(&f.input)
        guard case .variable(let idx) = f.arena.node(at: ref) else {
            Issue.record("expected bare `set` variable")
            return
        }
        #expect(f.arena.string(idx) == "set")
        #expect(f.input == " ()")
    }

    // MARK: Spans

    @Test
    func arraySpanCoversBrackets() throws {
        let f = Fixture("[1, 2, 3]")
        let ref = try f.grammar.parseTerm(&f.input)
        let s = f.arena.span(of: ref)
        #expect(s.start.offset == 0)
        #expect(s.end.offset == 9)
    }

    @Test
    func objectSpanCoversBraces() throws {
        let f = Fixture(#"{"a": 1}"#)
        let ref = try f.grammar.parseTerm(&f.input)
        let s = f.arena.span(of: ref)
        #expect(s.start.offset == 0)
        #expect(s.end.offset == 8)
    }
}
