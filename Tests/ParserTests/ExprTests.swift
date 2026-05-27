//
//  ExprTests.swift
//  Phase 4 — expression parser tests via @testable Grammar.parseExpr.
//

import Foundation
import Testing

@testable import Parser

@Suite
struct ParserPhase4ExprTests {
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

    // MARK: Single-term expressions

    @Test
    func parsesBareVariable() throws {
        let f = Fixture("foo")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .variable(let idx) = f.arena.node(at: ref) else {
            Issue.record("expected variable")
            return
        }
        #expect(f.arena.string(idx) == "foo")
    }

    // MARK: Parens

    @Test
    func parsesParenthesisedExpr() throws {
        let f = Fixture("(1 + 2)")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .parens(let inner) = f.arena.node(at: ref) else {
            Issue.record("expected parens")
            return
        }
        guard case .binary(.add, _, _) = f.arena.node(at: inner) else {
            Issue.record("expected add inside parens")
            return
        }
    }

    @Test
    func parensControlPrecedence() throws {
        let f = Fixture("2 * (3 + 4)")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .binary(.mul, _, let rhs) = f.arena.node(at: ref) else {
            Issue.record("expected mul at top")
            return
        }
        guard case .parens(let inner) = f.arena.node(at: rhs),
            case .binary(.add, _, _) = f.arena.node(at: inner)
        else {
            Issue.record("expected (3 + 4) under rhs")
            return
        }
    }

    @Test
    func unterminatedParens() {
        let f = Fixture("(1 + 2")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseExpr(&f.input)
        }
    }

    // MARK: Unary minus

    @Test
    func unaryMinusOnNumberStaysAsScalarNumber() throws {
        // `-NUMBER` is parsed as a signed scalar number (parseScalar
        // handles the leading `-`), not wrapped in a `unary` node.
        let f = Fixture("-42")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .scalarNumber(let idx) = f.arena.node(at: ref) else {
            Issue.record("expected scalarNumber")
            return
        }
        #expect(f.arena.string(idx) == "-42")
    }

    @Test
    func unaryMinusOnVariable() throws {
        let f = Fixture("-x")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .unary(.minus, let operand) = f.arena.node(at: ref) else {
            Issue.record("expected unary minus")
            return
        }
        guard case .variable = f.arena.node(at: operand) else {
            Issue.record("expected variable operand")
            return
        }
    }

    // MARK: Infix arithmetic + precedence

    @Test
    func parsesBasicAddition() throws {
        let f = Fixture("1 + 2")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .binary(.add, _, _) = f.arena.node(at: ref) else {
            Issue.record("expected add")
            return
        }
    }

    @Test
    func multiplicationBindsTighterThanAddition() throws {
        // `1 + 2 * 3` should parse as `1 + (2 * 3)`.
        let f = Fixture("1 + 2 * 3")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .binary(.add, _, let rhs) = f.arena.node(at: ref) else {
            Issue.record("expected add at top")
            return
        }
        guard case .binary(.mul, _, _) = f.arena.node(at: rhs) else {
            Issue.record("expected mul on the right")
            return
        }
    }

    @Test
    func leftAssociativity() throws {
        // `1 - 2 - 3` should parse as `(1 - 2) - 3`.
        let f = Fixture("1 - 2 - 3")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .binary(.sub, let lhs, _) = f.arena.node(at: ref),
            case .binary(.sub, _, _) = f.arena.node(at: lhs)
        else {
            Issue.record("expected ((1 - 2) - 3)")
            return
        }
    }

    @Test
    func boolOperatorsRecognised() throws {
        let cases: [(String, BinOp)] = [
            ("a == b", .eq),
            ("a != b", .ne),
            ("a < b", .lt),
            ("a <= b", .le),
            ("a > b", .gt),
            ("a >= b", .ge),
        ]
        for (input, expected) in cases {
            let f = Fixture(input)
            let ref = try f.grammar.parseExpr(&f.input)
            guard case .binary(let op, _, _) = f.arena.node(at: ref) else {
                Issue.record("\(input): expected binary")
                continue
            }
            #expect(op == expected, "\(input)")
        }
    }

    @Test
    func binaryAndUnifyOperators() throws {
        let cases: [(String, BinOp)] = [
            ("x | y", .bitOr),
            ("x & y", .bitAnd),
            ("x := 1", .assign),
            ("x = 1", .unify),
            ("x in y", .in),
        ]
        for (input, expected) in cases {
            let f = Fixture(input)
            let ref = try f.grammar.parseExpr(&f.input)
            guard case .binary(let op, _, _) = f.arena.node(at: ref) else {
                Issue.record("\(input): expected binary")
                continue
            }
            #expect(op == expected, "\(input)")
        }
    }

    @Test
    func equalityBindsLooserThanArithmetic() throws {
        // `a + 1 == b * 2` should parse as `(a + 1) == (b * 2)`.
        let f = Fixture("a + 1 == b * 2")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .binary(.eq, let lhs, let rhs) = f.arena.node(at: ref),
            case .binary(.add, _, _) = f.arena.node(at: lhs),
            case .binary(.mul, _, _) = f.arena.node(at: rhs)
        else {
            Issue.record("expected (a + 1) == (b * 2)")
            return
        }
    }

    @Test
    func assignBindsTighterThanLogicalAnd() throws {
        // `a := 1 and b := 2` should parse as `(a := 1) and (b := 2)`.
        let f = Fixture("a := 1 and b := 2")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .logical(.and, let lhs, let rhs) = f.arena.node(at: ref),
            case .binary(.assign, _, _) = f.arena.node(at: lhs),
            case .binary(.assign, _, _) = f.arena.node(at: rhs)
        else {
            Issue.record("expected (a := 1) and (b := 2)")
            return
        }
    }

    @Test
    func inOperatorAtBoolPrecedence() throws {
        let f = Fixture("a + 1 in xs")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .binary(.in, let lhs, _) = f.arena.node(at: ref),
            case .binary(.add, _, _) = f.arena.node(at: lhs)
        else {
            Issue.record("expected (a + 1) in xs")
            return
        }
    }

    @Test
    func indexedIdentifierIsNotKeywordIn() throws {
        // `index_var` should not match the `in` keyword and stay as a single
        // variable identifier.
        let f = Fixture("index_var")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .variable(let idx) = f.arena.node(at: ref) else {
            Issue.record("expected variable")
            return
        }
        #expect(f.arena.string(idx) == "index_var")
    }

    // MARK: Logical and / or

    @Test
    func logicalAndRecognised() throws {
        let f = Fixture("a and b")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .logical(.and, _, _) = f.arena.node(at: ref) else {
            Issue.record("expected and")
            return
        }
    }

    @Test
    func logicalOrRecognised() throws {
        let f = Fixture("a or b")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .logical(.or, _, _) = f.arena.node(at: ref) else {
            Issue.record("expected or")
            return
        }
    }

    @Test
    func andTighterThanOr() throws {
        // `a or b and c` should parse as `a or (b and c)`.
        let f = Fixture("a or b and c")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .logical(.or, _, let rhs) = f.arena.node(at: ref),
            case .logical(.and, _, _) = f.arena.node(at: rhs)
        else {
            Issue.record("expected a or (b and c)")
            return
        }
    }

    // MARK: Function calls

    @Test
    func parsesNoArgCall() throws {
        let f = Fixture("f()")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .call(let callee, let args) = f.arena.node(at: ref),
            args.isEmpty,
            case .variable = f.arena.node(at: callee)
        else {
            Issue.record("expected call")
            return
        }
    }

    @Test
    func parsesCallWithArgs() throws {
        let f = Fixture("f(1, 2, 3)")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .call(_, let args) = f.arena.node(at: ref), args.count == 3 else {
            Issue.record("expected call with 3 args")
            return
        }
    }

    @Test
    func parsesCallWithExpressionArgs() throws {
        let f = Fixture("f(a + b, c * d)")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .call(_, let args) = f.arena.node(at: ref), args.count == 2 else {
            Issue.record("expected 2 args")
            return
        }
        guard case .binary(.add, _, _) = f.arena.node(at: args[0]),
            case .binary(.mul, _, _) = f.arena.node(at: args[1])
        else {
            Issue.record("expected binary args")
            return
        }
    }

    @Test
    func parsesCallOnDottedRef() throws {
        let f = Fixture("a.b.c(x)")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .call(let callee, _) = f.arena.node(at: ref),
            case .ref = f.arena.node(at: callee)
        else {
            Issue.record("expected call on ref")
            return
        }
    }

    @Test
    func chainsRefArgsAfterCall() throws {
        // `f(x).bar` — call followed by a dot ref-arg.
        let f = Fixture("f(x).bar")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .ref(let head, let args) = f.arena.node(at: ref),
            args.count == 1,
            case .call = f.arena.node(at: head),
            case .refArgDot = f.arena.node(at: args[0])
        else {
            Issue.record("expected ref(call(...), [.bar])")
            return
        }
    }

    @Test
    func chainsCallAfterCall() throws {
        // `f()(x)` — call returning a function which is then called.
        let f = Fixture("f()(x)")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .call(let outerCallee, _) = f.arena.node(at: ref),
            case .call = f.arena.node(at: outerCallee)
        else {
            Issue.record("expected nested calls")
            return
        }
    }

    @Test
    func unterminatedCallArgs() {
        let f = Fixture("f(1, 2")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseExpr(&f.input)
        }
    }

    // MARK: Bracket ref args

    @Test
    func bracketRefArgOnVariable() throws {
        let f = Fixture("xs[i]")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .ref(let head, let args) = f.arena.node(at: ref),
            args.count == 1,
            case .variable = f.arena.node(at: head),
            case .refArgBracket(let inner) = f.arena.node(at: args[0]),
            case .variable = f.arena.node(at: inner)
        else {
            Issue.record("expected ref with bracket arg")
            return
        }
    }

    @Test
    func bracketRefArgWithExpression() throws {
        let f = Fixture("xs[i + 1]")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .ref(_, let args) = f.arena.node(at: ref),
            args.count == 1,
            case .refArgBracket(let inner) = f.arena.node(at: args[0]),
            case .binary(.add, _, _) = f.arena.node(at: inner)
        else {
            Issue.record("expected bracket with add inside")
            return
        }
    }

    @Test
    func bracketRefArgOnComposite() throws {
        let f = Fixture("[1, 2, 3][0]")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .ref(let head, let args) = f.arena.node(at: ref),
            args.count == 1,
            case .array = f.arena.node(at: head),
            case .refArgBracket = f.arena.node(at: args[0])
        else {
            Issue.record("expected ref(array, [bracket])")
            return
        }
    }

    @Test
    func mixedRefArgs() throws {
        // `data.users[id].role` — dot, bracket, dot.
        let f = Fixture("data.users[id].role")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .ref(_, let args) = f.arena.node(at: ref), args.count == 3 else {
            Issue.record("expected 3 ref args")
            return
        }
        guard case .refArgDot = f.arena.node(at: args[0]),
            case .refArgBracket = f.arena.node(at: args[1]),
            case .refArgDot = f.arena.node(at: args[2])
        else {
            Issue.record("expected dot, bracket, dot")
            return
        }
    }

    @Test
    func unterminatedBracketArg() {
        let f = Fixture("xs[i")
        #expect(throws: ParseError.self) {
            _ = try f.grammar.parseExpr(&f.input)
        }
    }

    // MARK: every

    @Test
    func everyKeywordParses() throws {
        let f = Fixture("every x in xs { x > 0 }")
        let ref = try f.grammar.parseExpr(&f.input)
        guard case .every(_, _, _, let body) = f.arena.node(at: ref),
            case .query = f.arena.node(at: body)
        else {
            Issue.record("expected every with query body")
            return
        }
    }
}
