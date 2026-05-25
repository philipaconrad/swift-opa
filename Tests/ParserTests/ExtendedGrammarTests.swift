//
//  ExtendedGrammarTests.swift
//  Phase 6+ regression coverage for grammar extensions added on top of the
//  initial v1-strict baseline:
//
//    - Comma-form membership terms (`a, b in c`)
//    - Multi-line `with` modifier continuation
//    - Keyword identifiers as ref atoms (`else.foo`, `with.bar`, `in.baz`, …)
//    - Extended `some` (composite term LHS)
//    - Comprehension-as-rule-body
//    - Template expressions with `with` modifiers
//    - Ref-head rules with multiple bracket / dot args
//

import Foundation
import Testing

@testable import Parser

@Suite
struct ExtendedGrammarTests {
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

    private func parseModule(_ src: String) -> Result<SyntaxArena, ParseErrors> {
        Parser.parse(
            source: SourceFile(
                url: URL(fileURLWithPath: "test.rego"), bundleID: nil, contents: src))
    }

    // MARK: Comma-form membership

    @Test
    func commaMembershipInsideParens() throws {
        let f = Fixture("(1, 2 in [2])")
        let ref = try f.grammar.parseExpr(&f.input, allowComma: true)
        guard case .parens(let inner) = f.arena.node(at: ref),
            case .membership(let key, _, _) = f.arena.node(at: inner)
        else {
            Issue.record("expected parens(membership)")
            return
        }
        #expect(key != nil)
    }

    @Test
    func commaMembershipAtLiteralLevel() throws {
        let f = Fixture(#""foo", 1 in {"foo": 1}"#)
        let ref = try f.grammar.parseLiteral(&f.input)
        guard case .membership(let key, let value, _) = f.arena.node(at: ref),
            let key
        else {
            Issue.record("expected membership at literal level with key")
            return
        }
        guard case .scalarString = f.arena.node(at: key) else {
            Issue.record("expected string key")
            return
        }
        guard case .scalarNumber = f.arena.node(at: value) else {
            Issue.record("expected number value")
            return
        }
    }

    @Test
    func commaMembershipNestedWithoutParens() throws {
        // Per OPA tests: `1, 2 in [2] in [false, true]` parses as
        // `membership(1, (2 in [2]), [false, true])`.
        let f = Fixture("1, 2 in [2] in [false, true]")
        let ref = try f.grammar.parseLiteral(&f.input)
        guard case .membership(_, let value, let domain) = f.arena.node(at: ref) else {
            Issue.record("expected membership")
            return
        }
        guard case .binary(.in, _, _) = f.arena.node(at: value) else {
            Issue.record("expected (binary in) as value")
            return
        }
        guard case .array = f.arena.node(at: domain) else {
            Issue.record("expected array domain")
            return
        }
    }

    @Test
    func bareCommaIsNotMembership() throws {
        // `[1, 2, 3]` — commas separate array elements, not membership.
        let f = Fixture("[1, 2, 3]")
        let ref = try f.grammar.parseExpr(&f.input, allowComma: true)
        guard case .array(let elements) = f.arena.node(at: ref), elements.count == 3 else {
            Issue.record("expected 3-element array")
            return
        }
    }

    // MARK: Multi-line `with` modifier continuation

    @Test
    func multiLineWithModifier() throws {
        let src = """
            package test

            test_allow if {
                allow with input.a as 1
                    with input.b as 2
                    with http.send as mock
            }

            allow if true
            """
        guard case .success = parseModule(src) else {
            Issue.record("expected success")
            return
        }
    }

    // MARK: Keyword identifiers as ref atoms

    @Test
    func reservedWordAsRefHeadInExpression() throws {
        let f = Fixture("else.foo == 1")
        let ref = try f.grammar.parseLiteral(&f.input)
        guard case .binary(.eq, let lhs, _) = f.arena.node(at: ref),
            case .ref(let head, let args) = f.arena.node(at: lhs)
        else {
            Issue.record("expected binary eq with ref lhs")
            return
        }
        guard case .variable = f.arena.node(at: head), args.count == 1 else {
            Issue.record("expected variable head with 1 dot arg")
            return
        }
    }

    @Test
    func reservedWordAsRefHeadInRuleHead() throws {
        let src = """
            package test

            null.foo := 1

            else.bar contains "x"

            with.baz(y) := y if true
            """
        guard case .success(let arena) = parseModule(src),
            let root = arena.root,
            case .module(_, _, let rules) = arena.node(at: root)
        else {
            Issue.record("expected success with 3 rules")
            return
        }
        #expect(rules.count == 3)
    }

    @Test
    func bareReservedWordStillRejectedAsExpression() throws {
        let f = Fixture("else == 1")
        #expect(throws: ParseError.self) {
            try f.grammar.parseLiteral(&f.input)
        }
    }

    @Test
    func ifKeywordAfterRuleNotConsumedAsRuleHead() throws {
        // `if.foo contains "a"` is a rule. The `if` should not be picked
        // up as the body keyword for the previous rule.
        let src = """
            package test

            users contains "alice"

            if.foo contains "a"
            """
        guard case .success(let arena) = parseModule(src),
            let root = arena.root,
            case .module(_, _, let rules) = arena.node(at: root)
        else {
            Issue.record("expected 2 rules")
            return
        }
        #expect(rules.count == 2)
    }

    // MARK: `some` extended forms

    @Test
    func someWithLiteralValue() throws {
        let f = Fixture(#"some "foo" in ["foo"]"#)
        let ref = try f.grammar.parseLiteral(&f.input)
        guard case .someIn(let key, let value, _) = f.arena.node(at: ref) else {
            Issue.record("expected someIn")
            return
        }
        #expect(key == nil)
        guard case .scalarString = f.arena.node(at: value) else {
            Issue.record("expected string value")
            return
        }
    }

    @Test
    func someWithCompositeTerm() throws {
        let f = Fixture(#"some {"foo": x} in [{"foo": 100}]"#)
        let ref = try f.grammar.parseLiteral(&f.input)
        guard case .someIn(_, let value, _) = f.arena.node(at: ref),
            case .object = f.arena.node(at: value)
        else {
            Issue.record("expected someIn with object value")
            return
        }
    }

    @Test
    func someWithKeyAndCompositeValue() throws {
        let f = Fixture(#"some y, {"c": x} in data.array"#)
        let ref = try f.grammar.parseLiteral(&f.input)
        guard case .someIn(let key, let value, _) = f.arena.node(at: ref),
            key != nil,
            case .object = f.arena.node(at: value)
        else {
            Issue.record("expected someIn(key, object)")
            return
        }
    }

    @Test
    func someBareVarsRejectsNonVariableTerm() throws {
        // `some "foo"` (no `in`) should be rejected — bare `some` only
        // declares variable names.
        let f = Fixture(#"some "foo""#)
        #expect(throws: ParseError.self) {
            try f.grammar.parseLiteral(&f.input)
        }
    }

    // MARK: Comprehension-as-rule-body

    @Test
    func comprehensionAsRuleBody() throws {
        let src = """
            package test

            f(x) := x if {y: i | y := ["a", "b"][i]}
            """
        guard case .success(let arena) = parseModule(src),
            let root = arena.root,
            case .module(_, _, let rules) = arena.node(at: root),
            let rule = rules.first,
            case .rule(_, _, let body, _) = arena.node(at: rule),
            let body
        else {
            Issue.record("expected rule with body")
            return
        }
        guard case .query(let lits) = arena.node(at: body),
            lits.count == 1,
            case .objectCompr = arena.node(at: lits[0])
        else {
            Issue.record("expected single-literal body wrapping object comprehension")
            return
        }
    }

    @Test
    func braceQueryBodyStillWorks() throws {
        // Make sure non-comprehension brace-bodies still parse as queries.
        let src = """
            package test

            allow if { x == 1; y == 2 }
            """
        guard case .success(let arena) = parseModule(src),
            let root = arena.root,
            case .module(_, _, let rules) = arena.node(at: root),
            let rule = rules.first,
            case .rule(_, _, let body, _) = arena.node(at: rule),
            let body,
            case .query(let lits) = arena.node(at: body),
            lits.count == 2
        else {
            Issue.record("expected 2-literal query body")
            return
        }
    }

    // MARK: Template expressions with `with` modifiers

    @Test
    func templateExpressionWithModifier() throws {
        let f = Fixture(#"$"foo {a with input as 1}""#)
        let ref = try f.grammar.parseScalar(&f.input)
        guard case .templateString(let parts, _) = f.arena.node(at: ref),
            parts.count == 2  // "foo " literal + expr
        else {
            Issue.record("expected template with literal + expr")
            return
        }
        guard case .templateExpr(let exprRef) = f.arena.node(at: parts[1]) else {
            Issue.record("expected templateExpr")
            return
        }
        // The inner expr should be a literal carrying the `with` modifier.
        guard case .literal(_, let mods) = f.arena.node(at: exprRef), !mods.isEmpty else {
            Issue.record("expected literal with `with` modifier")
            return
        }
    }

    // MARK: Ref-head rules with arbitrary args

    @Test
    func refHeadRuleWithDeepRef() throws {
        let f = Fixture("p.allow[action][resource] := result if cond")
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(_, let head, _, _) = f.arena.node(at: ref),
            case .ruleHead(let name, _, let value, let hasIf) = f.arena.node(at: head)
        else {
            Issue.record("expected ruleHead")
            return
        }
        #expect(value != nil)
        #expect(hasIf)
        guard case .ref(_, let args) = f.arena.node(at: name), args.count == 3 else {
            Issue.record("expected name ref with 3 ref-args")
            return
        }
    }

    @Test
    func refHeadRuleSetForm() throws {
        let f = Fixture(#"p[q].r contains s if true"#)
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(_, let head, _, _) = f.arena.node(at: ref),
            case .ruleHead(let name, let kind, _, _) = f.arena.node(at: head),
            case .set = kind,
            case .ref(_, let args) = f.arena.node(at: name),
            args.count == 2
        else {
            Issue.record("expected set-head rule with 2 ref-args on name")
            return
        }
    }

    @Test
    func valueIsExpressionNotJustTerm() throws {
        // `:= a + b` — value position must accept full expressions.
        let f = Fixture("foo(a, b) := a + b if true")
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(_, let head, _, _) = f.arena.node(at: ref),
            case .ruleHead(_, _, let value, _) = f.arena.node(at: head),
            let value,
            case .binary(.add, _, _) = f.arena.node(at: value)
        else {
            Issue.record("expected rule with binary-add value")
            return
        }
    }
}
