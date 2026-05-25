//
//  RuleTests.swift
//  Phase 6 — rule heads, bodies, else-clauses.
//

import Foundation
import Testing

@testable import Parser

@Suite
struct ParserPhase6RuleTests {
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

    // MARK: Constant rules (rule-head-comp)

    @Test
    func parsesConstantRule() throws {
        let f = Fixture("pi := 3.14159")
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(let isDefault, let head, let body, let elses) = f.arena.node(at: ref) else {
            Issue.record("expected rule node")
            return
        }
        #expect(!isDefault)
        #expect(body == nil)
        #expect(elses.isEmpty)
        guard case .ruleHead(_, let kind, let value, let hasIf) = f.arena.node(at: head) else {
            Issue.record("expected ruleHead")
            return
        }
        #expect(value != nil)
        #expect(!hasIf)
        guard case .complete = kind else {
            Issue.record("expected complete head")
            return
        }
    }

    @Test
    func parsesDefaultRule() throws {
        let f = Fixture("default allow := false")
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(let isDefault, _, _, _) = f.arena.node(at: ref) else {
            Issue.record("expected rule node")
            return
        }
        #expect(isDefault)
    }

    @Test
    func parsesRuleWithIfBody() throws {
        let f = Fixture(#"allow if user == "admin""#)
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(_, let head, let body, _) = f.arena.node(at: ref) else {
            Issue.record("expected rule node")
            return
        }
        #expect(body != nil)
        guard case .ruleHead(_, _, _, let hasIf) = f.arena.node(at: head) else {
            Issue.record("expected ruleHead")
            return
        }
        #expect(hasIf)
    }

    @Test
    func parsesRuleWithBraceBody() throws {
        let f = Fixture(#"allow if { user == "admin"; method == "GET" }"#)
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(_, _, let body, _) = f.arena.node(at: ref), let body else {
            Issue.record("expected rule with body")
            return
        }
        guard case .query(let lits) = f.arena.node(at: body), lits.count == 2 else {
            Issue.record("expected 2-literal query body")
            return
        }
    }

    @Test
    func parsesRuleWithIfAndBraceBody() throws {
        // Per the v1-strict policy, `if` introduces a body that may be a
        // single literal OR a `{ … }` query.
        let f = Fixture("allow if { x }")
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(_, _, let body, _) = f.arena.node(at: ref), let body else {
            Issue.record("expected rule with body")
            return
        }
        guard case .query = f.arena.node(at: body) else {
            Issue.record("expected query body")
            return
        }
    }

    // MARK: Object heads (now: complete head with bracket ref-arg)

    @Test
    func parsesObjectHeadRule() throws {
        let f = Fixture("users[id] := info if user_data[id]")
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(_, let head, _, _) = f.arena.node(at: ref) else {
            Issue.record("expected rule node")
            return
        }
        guard case .ruleHead(let name, let kind, let value, _) = f.arena.node(at: head) else {
            Issue.record("expected ruleHead")
            return
        }
        #expect(value != nil)
        // After unification, `users[id]` is a complete head whose name ref
        // carries one bracket arg.
        guard case .complete = kind else {
            Issue.record("expected complete head")
            return
        }
        guard case .ref(_, let args) = f.arena.node(at: name), args.count == 1,
            case .refArgBracket = f.arena.node(at: args[0])
        else {
            Issue.record("expected name ref with one bracket arg")
            return
        }
    }

    @Test
    func parsesRefHeadWithMultipleBrackets() throws {
        let f = Fixture("p.allow[action][resource] if cond")
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(_, let head, _, _) = f.arena.node(at: ref),
            case .ruleHead(let name, let kind, _, let hasIf) = f.arena.node(at: head)
        else {
            Issue.record("expected ruleHead")
            return
        }
        #expect(hasIf)
        guard case .complete = kind else {
            Issue.record("expected complete head")
            return
        }
        guard case .ref(_, let args) = f.arena.node(at: name), args.count == 3 else {
            Issue.record("expected name ref with 3 args (.allow [action] [resource])")
            return
        }
    }

    @Test
    func rejectsLegacyBracketSetHead() throws {
        let f = Fixture("box[x]")
        #expect(throws: ParseError.self) {
            try f.grammar.parseRule(&f.input)
        }
    }

    // MARK: Set heads (contains)

    @Test
    func parsesContainsSetRule() throws {
        let f = Fixture(#"admin_users contains "alice" if true"#)
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(_, let head, _, _) = f.arena.node(at: ref) else {
            Issue.record("expected rule node")
            return
        }
        guard case .ruleHead(_, let kind, _, let hasIf) = f.arena.node(at: head) else {
            Issue.record("expected ruleHead")
            return
        }
        #expect(hasIf)
        guard case .set = kind else {
            Issue.record("expected set head")
            return
        }
    }

    // MARK: Function heads

    @Test
    func parsesFunctionRule() throws {
        let f = Fixture("double(x) := y if y := x * 2")
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(_, let head, _, _) = f.arena.node(at: ref) else {
            Issue.record("expected rule node")
            return
        }
        guard case .ruleHead(_, let kind, let value, _) = f.arena.node(at: head) else {
            Issue.record("expected ruleHead")
            return
        }
        #expect(value != nil)
        guard case .function(let args) = kind, args.count == 1 else {
            Issue.record("expected function head with 1 arg")
            return
        }
    }

    @Test
    func parsesFunctionRuleMultipleArgs() throws {
        let f = Fixture("add(x, y) := x + y if true")
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(_, let head, _, _) = f.arena.node(at: ref) else {
            Issue.record("expected rule node")
            return
        }
        guard case .ruleHead(_, let kind, _, _) = f.arena.node(at: head),
            case .function(let args) = kind, args.count == 2
        else {
            Issue.record("expected function head with 2 args")
            return
        }
    }

    // MARK: Else clauses

    @Test
    func parsesSingleElseClause() throws {
        let f = Fixture("a := 5 if cond1 else := 10 if cond2")
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(_, _, _, let elses) = f.arena.node(at: ref), elses.count == 1 else {
            Issue.record("expected exactly 1 else clause")
            return
        }
        guard case .elseClause(let value, let body) = f.arena.node(at: elses[0]) else {
            Issue.record("expected elseClause node")
            return
        }
        #expect(value != nil)
        #expect(body != nil)
    }

    @Test
    func parsesElseChain() throws {
        let f = Fixture("a := 5 if cond1 else := 10 if cond2 else := 15")
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(_, _, _, let elses) = f.arena.node(at: ref), elses.count == 2 else {
            Issue.record("expected 2 else clauses")
            return
        }
        guard case .elseClause(let v2, let b2) = f.arena.node(at: elses[1]) else {
            Issue.record("expected elseClause")
            return
        }
        #expect(v2 != nil)
        // No `if`, no `{` → no body.
        #expect(b2 == nil)
    }

    @Test
    func parsesElseWithBraceBody() throws {
        let f = Fixture("a := 5 if cond else := 10 { y == 1 }")
        let ref = try f.grammar.parseRule(&f.input)
        guard case .rule(_, _, _, let elses) = f.arena.node(at: ref), elses.count == 1 else {
            Issue.record("expected 1 else clause")
            return
        }
        guard case .elseClause(_, let body) = f.arena.node(at: elses[0]), body != nil else {
            Issue.record("expected else body")
            return
        }
    }

    // MARK: v1-strict rejections

    @Test
    func rejectsBraceBodyWithoutIf() throws {
        let f = Fixture("allow { user == \"admin\" }")
        #expect(throws: ParseError.self) {
            try f.grammar.parseRule(&f.input)
        }
    }

    // MARK: Multi-rule modules via Parser.parse

    @Test
    func parsesModuleWithMultipleRules() throws {
        let src = """
            package example

            allow if user == "admin"
            deny if user == "blocked"

            pi := 3.14
            """
        let source = SourceFile(url: URL(fileURLWithPath: "ex.rego"), bundleID: nil, contents: src)
        let result = Parser.parse(source: source)
        guard case .success(let arena) = result else {
            if case .failure(let errs) = result {
                Issue.record("parse failed: \(errs)")
            }
            return
        }
        guard let root = arena.root,
            case .module(_, _, let rules) = arena.node(at: root)
        else {
            Issue.record("expected module root")
            return
        }
        #expect(rules.count == 3)
    }

    // MARK: Spans

    @Test
    func ruleSpanCoversFullRule() throws {
        let f = Fixture("pi := 3.14")
        let ref = try f.grammar.parseRule(&f.input)
        let s = f.arena.span(of: ref)
        #expect(s.start.offset == 0)
        #expect(s.end.offset == UInt32("pi := 3.14".count))
    }

    // MARK: Errors

    @Test
    func errorOnMissingFunctionParen() throws {
        let f = Fixture("foo(x")
        #expect(throws: ParseError.self) {
            try f.grammar.parseRule(&f.input)
        }
    }

    @Test
    func errorOnMissingBraceBodyClose() throws {
        let f = Fixture("foo if { x ; y ")
        #expect(throws: ParseError.self) {
            try f.grammar.parseRule(&f.input)
        }
    }
}
