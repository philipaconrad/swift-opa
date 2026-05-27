//
//  CommentBindingTests.swift
//  Coverage for `bindComments` and the `# METADATA` recogniser, plus
//  the round-trip behaviour of comment-bearing modules.
//
//  Three layered styles:
//
//    - Bind-shape tests verify that, given a source, the binding pass
//      labels comments correctly (leading/trailing/freestanding) and
//      attaches them to the right anchor.
//    - METADATA tests verify recognition of `# METADATA` headers and
//      the strip-and-default-scope behaviour.
//    - Round-trip tests assert that parsing a comment-bearing source
//      and printing it produces output that re-parses to the same
//      bindings (idempotent).
//

import Foundation
import Testing

@testable import Parser

@Suite
struct CommentBindingTests {
    private static func parse(_ src: String) -> SyntaxArena? {
        let source = SourceFile(
            url: URL(fileURLWithPath: "test.rego"), bundleID: nil, contents: src)
        guard case .success(let arena) = Parser.parse(source: source) else { return nil }
        return arena
    }

    private static func format(_ src: String) -> String? {
        guard let arena = parse(src) else { return nil }
        return Printer(arena: arena).print()
    }

    // MARK: - Bind shape (table-driven)
    //
    // Each case lists the comments and their expected position. Comments
    // are addressed by the substring of their text (after `# `) for
    // readability. Targets are addressed by a "tag" — the rule's name
    // for top-level rules, or a literal's text snippet for body
    // literals.

    enum ExpectedTarget: Hashable, Sendable {
        case rule(String)  // matched by rule head name
        case packageDecl
        case importDecl(String)  // matched by import path
        case literal(String)  // matched by literal's emit prefix
        case freestanding
    }

    struct BindCase {
        let name: String
        let source: String
        /// (commentTextAfterHash, expectedTarget, expectedPosition).
        /// Missing comments are treated as a test failure.
        let expectations: [(text: String, target: ExpectedTarget, position: CommentPosition?)]
    }

    static let bindCases: [BindCase] = [
        BindCase(
            name: "simple leading on rule",
            source: """
                package x

                # constant
                pi := 3.14
                """,
            expectations: [
                ("# constant", .rule("pi"), .leading)
            ]
        ),
        BindCase(
            name: "trailing on rule",
            source: """
                package x

                pi := 3.14 # explanation
                """,
            expectations: [
                ("# explanation", .rule("pi"), .trailing)
            ]
        ),
        BindCase(
            name: "leading on import",
            source: """
                package x

                # data set
                import data.foo

                allow := true
                """,
            expectations: [
                ("# data set", .importDecl("data.foo"), .leading)
            ]
        ),
        BindCase(
            name: "freestanding between rules",
            source: """
                package x

                pi := 3.14

                # divider

                e := 2.71
                """,
            expectations: [
                ("# divider", .freestanding, nil)
            ]
        ),
        BindCase(
            name: "leading on body literal",
            source: """
                package x

                allow if {
                \t# check
                \tx == 1
                }
                """,
            expectations: [
                ("# check", .literal("x == 1"), .leading)
            ]
        ),
        BindCase(
            name: "trailing on body literal",
            source: """
                package x

                allow if {
                \tx == 1 # check
                \ty == 2
                }
                """,
            expectations: [
                ("# check", .literal("x == 1"), .trailing)
            ]
        ),
        BindCase(
            name: "multiple leading lines on rule",
            source: """
                package x

                # line one
                # line two
                # line three
                allow if true
                """,
            expectations: [
                ("# line one", .rule("allow"), .leading),
                ("# line two", .rule("allow"), .leading),
                ("# line three", .rule("allow"), .leading),
            ]
        ),
        BindCase(
            name: "blank line gap unbinds non-METADATA",
            source: """
                package x

                # orphan

                allow if true
                """,
            expectations: [
                ("# orphan", .freestanding, nil)
            ]
        ),
    ]

    @Test("bind shape", arguments: bindCases)
    func bindShape(c: BindCase) throws {
        guard let arena = Self.parse(c.source) else {
            Issue.record("[\(c.name)] parse failed")
            return
        }
        let bindings = arena.bindings

        for exp in c.expectations {
            // Find the comment by exact text match.
            guard let comment = arena.comments.first(where: { $0.text == exp.text }) else {
                Issue.record(
                    "[\(c.name)] comment '\(exp.text)' not in arena.comments — got: \(arena.comments.map { $0.text })"
                )
                continue
            }

            switch exp.target {
            case .freestanding:
                #expect(
                    bindings.freestanding.contains(where: { $0 == comment }),
                    "[\(c.name)] expected '\(exp.text)' to be freestanding")
            default:
                guard let targetRef = Self.findTarget(exp.target, in: arena) else {
                    Issue.record("[\(c.name)] couldn't find target for '\(exp.text)'")
                    continue
                }
                // Looked up positionally; type inferred to avoid the
                // `Comment` ambiguity between `Parser.Comment` and the
                // Swift Testing `Testing.Comment`.
                let onTarget = bindings.commentsForPosition(exp.position, of: targetRef)
                #expect(
                    onTarget.contains(where: { $0 == comment }),
                    "[\(c.name)] expected '\(exp.text)' on \(exp.target) at \(exp.position?.description ?? "?")"
                )
            }
        }
    }

    private static func findTarget(_ target: ExpectedTarget, in arena: SyntaxArena) -> NodeRef? {
        guard let root = arena.root,
            case .module(let pkg, let imports, let rules) = arena.node(at: root)
        else { return nil }

        switch target {
        case .packageDecl:
            return pkg
        case .importDecl(let path):
            for imp in imports {
                if case .importDecl(let pathRef, _) = arena.node(at: imp),
                    refDottedString(pathRef, in: arena) == path
                {
                    return imp
                }
            }
            return nil
        case .rule(let name):
            for r in rules {
                if case .rule(_, let head, _, _) = arena.node(at: r),
                    case .ruleHead(let nameRef, _, _, _) = arena.node(at: head),
                    refDottedString(nameRef, in: arena) == name
                {
                    return r
                }
            }
            return nil
        case .literal(let text):
            // Walk and find a literal whose emit starts with `text`.
            let printer = Printer(arena: arena)
            for r in rules {
                if let found = findLiteral(rootRef: r, prefix: text, arena: arena, printer: printer) {
                    return found
                }
            }
            return nil
        case .freestanding:
            return nil
        }
    }

    private static func findLiteral(
        rootRef: NodeRef, prefix: String, arena: SyntaxArena, printer: Printer
    )
        -> NodeRef?
    {
        var found: NodeRef?
        arena.walk(from: rootRef) { ref in
            if found != nil { return }
            if case .query(let lits) = arena.node(at: ref) {
                for lit in lits where printer.print(lit).hasPrefix(prefix) {
                    found = lit
                    return
                }
            }
        }
        return found
    }

    private static func refDottedString(_ ref: NodeRef, in arena: SyntaxArena) -> String? {
        guard case .ref(let head, let args) = arena.node(at: ref),
            case .variable(let headIdx) = arena.node(at: head)
        else { return nil }
        var parts = [arena.string(headIdx)]
        for arg in args {
            guard case .refArgDot(let idx) = arena.node(at: arg) else { return nil }
            parts.append(arena.string(idx))
        }
        return parts.joined(separator: ".")
    }

    // MARK: - METADATA recognition

    @Test
    func recognisesMetadataOnPackage() throws {
        let src = """
            # METADATA
            # title: My package
            # description: Stuff
            package x
            """
        guard let arena = Self.parse(src) else {
            Issue.record("parse failed")
            return
        }
        let blocks = arena.bindings.metadataBlocks
        #expect(blocks.count == 1)
        guard let block = blocks.first else { return }
        #expect(block.lines == ["title: My package", "description: Stuff"])
        #expect(block.defaultScope == .package)
    }

    @Test
    func recognisesMetadataOnRule() throws {
        let src = """
            package x

            # METADATA
            # title: Allow rule
            # entrypoint: true
            allow if true
            """
        guard let arena = Self.parse(src) else {
            Issue.record("parse failed")
            return
        }
        let blocks = arena.bindings.metadataBlocks
        #expect(blocks.count == 1)
        guard let block = blocks.first else { return }
        #expect(block.lines == ["title: Allow rule", "entrypoint: true"])
        #expect(block.defaultScope == .rule)
    }

    @Test
    func metadataBindsAcrossBlankLineGap() throws {
        // Per OPA: a blank line ends the YAML body but METADATA still
        // binds to the next statement.
        let src = """
            # METADATA
            # title: Spans gap

            package x
            """
        guard let arena = Self.parse(src) else {
            Issue.record("parse failed")
            return
        }
        #expect(arena.bindings.metadataBlocks.count == 1)
        guard let pkgRef = arena.bindings.metadataBlocks.first?.target else { return }
        // Verify the leading comments are bound to the package.
        let leading = arena.bindings.leadingComments(of: pkgRef)
        #expect(leading.count == 2)
    }

    @Test
    func metadataAndPlainCommentMakeTwoGroups() throws {
        // When a blank line separates METADATA from a plain doc comment
        // that's still right above the rule, we end up with two leading
        // groups on the same target.
        let src = """
            package x

            # METADATA
            # title: M

            # additional doc
            allow if true
            """
        guard let arena = Self.parse(src) else {
            Issue.record("parse failed")
            return
        }
        // Find the allow rule.
        guard let root = arena.root,
            case .module(_, _, let rules) = arena.node(at: root),
            let rule = rules.first
        else {
            Issue.record("rule not found")
            return
        }
        let groups = arena.bindings.leadingGroups(of: rule)
        #expect(groups.count == 2)
        #expect(groups.first?.first?.text == "# METADATA")
        #expect(groups.last?.first?.text == "# additional doc")
    }

    // MARK: - Round-trip with comments

    /// Parse → print → parse → print idempotency. The printed output may
    /// differ from input (canonical formatting), but the second print
    /// must equal the first.
    static let roundTripCases: [String] = [
        // Simple leading
        "package x\n\n# constant\npi := 3.14",
        // Trailing same-line
        "package x\n\npi := 3.14 # the constant",
        // METADATA on rule
        """
        package x

        # METADATA
        # title: Allow
        allow if true
        """,
        // METADATA on package
        """
        # METADATA
        # scope: subpackages
        # title: My package
        package x.y
        """,
        // Leading on body literal
        """
        package x

        allow if {
        \t# check role
        \tuser.role == "admin"
        \t# and not banned
        \tnot user.banned
        }
        """,
        // Trailing on body literal
        """
        package x

        allow if {
        \tuser.role == "admin" # required
        \tnot user.banned
        }
        """,
        // Section divider freestanding
        """
        package x

        pi := 3.14

        # ============ HELPERS ============

        helper := false
        """,
        // Multiple imports with leading on one
        """
        package x

        import data.foo
        # alias for clarity
        import data.bar as b

        allow := true
        """,
    ]

    @Test("round-trip with comments", arguments: roundTripCases)
    func roundTripIdempotent(src: String) throws {
        guard let first = Self.format(src) else {
            Issue.record("first parse failed")
            return
        }
        guard let second = Self.format(first) else {
            Issue.record("re-parse failed:\n\(first)")
            return
        }
        #expect(first == second, "not idempotent\nfirst:\n\(first)\nsecond:\n\(second)")
    }

    // MARK: - Spot-check first-print output

    @Test
    func leadingCommentEmittedAboveRule() throws {
        let src = "package x\n\n# constant\npi := 3.14"
        guard let printed = Self.format(src) else {
            Issue.record("parse failed")
            return
        }
        #expect(printed.contains("# constant\npi := 3.14"))
    }

    @Test
    func trailingCommentEmittedOnSameLine() throws {
        let src = "package x\n\npi := 3.14 # explanation"
        guard let printed = Self.format(src) else {
            Issue.record("parse failed")
            return
        }
        #expect(printed.contains("pi := 3.14 # explanation"))
    }

    @Test
    func freestandingSectionDividerSurvives() throws {
        let src = "package x\n\npi := 3.14\n\n# helpers\n\nhelper := true"
        guard let printed = Self.format(src) else {
            Issue.record("parse failed")
            return
        }
        #expect(printed.contains("# helpers"))
    }
}

// `CommentPosition.description` for friendly assertion messages.
extension CommentPosition: CustomStringConvertible {
    public var description: String {
        switch self {
        case .leading: return "leading"
        case .trailing: return "trailing"
        }
    }
}
