//
//  ParserTests.swift
//  Phase 1 smoke tests: package declaration round-trip, comments, errors.
//

import Foundation
import Testing

@testable import Parser

@Suite
struct ParserPhase1Tests {
    private func sourceFile(_ contents: String) -> SourceFile {
        SourceFile(
            url: URL(fileURLWithPath: "test.rego"),
            bundleID: nil,
            contents: contents
        )
    }

    private func parseSuccessfully(_ contents: String) throws -> SyntaxArena {
        switch Parser.parse(source: sourceFile(contents)) {
        case .success(let arena):
            return arena
        case .failure(let errors):
            Issue.record("expected success but got errors: \(errors)")
            throw ExpectedSuccessError()
        }
    }

    private struct ExpectedSuccessError: Error {}

    @Test
    func parsesSimplePackage() throws {
        let arena = try parseSuccessfully("package foo")
        let root = try #require(arena.root)
        guard case .module(let pkgRef, let imports, let rules) = arena.node(at: root) else {
            Issue.record("expected module at root")
            return
        }
        #expect(imports.isEmpty)
        #expect(rules.isEmpty)

        guard case .packageDecl(let pathRef) = arena.node(at: pkgRef) else {
            Issue.record("expected packageDecl")
            return
        }
        guard case .ref(let headRef, let args) = arena.node(at: pathRef) else {
            Issue.record("expected ref under packageDecl")
            return
        }
        #expect(args.isEmpty)
        guard case .variable(let nameIdx) = arena.node(at: headRef) else {
            Issue.record("expected variable as ref head")
            return
        }
        #expect(arena.string(nameIdx) == "foo")
    }

    @Test
    func parsesDottedPackage() throws {
        let arena = try parseSuccessfully("package foo.bar.baz")
        let root = try #require(arena.root)
        guard case .module(let pkgRef, _, _) = arena.node(at: root),
            case .packageDecl(let pathRef) = arena.node(at: pkgRef),
            case .ref(let headRef, let args) = arena.node(at: pathRef)
        else {
            Issue.record("expected module → packageDecl → ref")
            return
        }
        guard case .variable(let headIdx) = arena.node(at: headRef) else {
            Issue.record("expected variable head")
            return
        }
        #expect(arena.string(headIdx) == "foo")
        #expect(args.count == 2)

        let collected = args.compactMap { ref -> String? in
            guard case .refArgDot(let s) = arena.node(at: ref) else { return nil }
            return arena.string(s)
        }
        #expect(collected == ["bar", "baz"])
    }

    @Test
    func recordsComments() throws {
        let arena = try parseSuccessfully(
            """
            # one
            # two
            package foo
            """
        )
        #expect(arena.comments.count == 2)
        #expect(arena.comments.map { $0.text } == ["# one", "# two"])

        let root = try #require(arena.root)
        let leading = arena.leadingComments(of: root)
        #expect(leading.count == 2)
        #expect(leading.map { $0.text } == ["# one", "# two"])
    }

    @Test
    func leadingCommentsRequireContiguousLines() throws {
        let arena = try parseSuccessfully(
            """
            # detached

            # attached one
            # attached two
            package foo
            """
        )
        let root = try #require(arena.root)
        let leading = arena.leadingComments(of: root)
        #expect(leading.map { $0.text } == ["# attached one", "# attached two"])
    }

    @Test
    func packageSpanCoversWholeDeclaration() throws {
        let arena = try parseSuccessfully("package foo.bar")
        let root = try #require(arena.root)
        guard case .module(let pkgRef, _, _) = arena.node(at: root) else {
            Issue.record("expected module")
            return
        }
        let pkgSpan = arena.span(of: pkgRef)
        #expect(pkgSpan.start.offset == 0)
        // "package foo.bar" is 15 characters.
        #expect(pkgSpan.end.offset == 15)
    }

    @Test
    func emptyInputFailsWithMissingPackage() {
        let result = Parser.parse(source: sourceFile(""))
        guard case .failure(let errors) = result else {
            Issue.record("expected failure on empty input")
            return
        }
        #expect(errors.errors.count == 1)
    }

    @Test
    func packageWithoutNameFails() {
        let result = Parser.parse(source: sourceFile("package "))
        guard case .failure(let errors) = result else {
            Issue.record("expected failure on lone keyword")
            return
        }
        #expect(
            errors.errors.contains { err in
                if case .expected(let what) = err.kind { return what == "identifier" }
                return false
            })
    }

    @Test
    func reservedWordAsHeadFails() {
        let result = Parser.parse(source: sourceFile("package if"))
        guard case .failure(let errors) = result else {
            Issue.record("expected failure on reserved word")
            return
        }
        #expect(
            errors.errors.contains { err in
                if case .reservedWord(let w) = err.kind { return w == "if" }
                return false
            })
    }

    @Test
    func reservedWordAllowedInRefArg() throws {
        // `data.input` works upstream — `input` is reserved as a head but
        // valid as a field name in a ref.
        let arena = try parseSuccessfully("package data.input")
        let root = try #require(arena.root)
        guard case .module(let pkgRef, _, _) = arena.node(at: root),
            case .packageDecl(let pathRef) = arena.node(at: pkgRef),
            case .ref(_, let args) = arena.node(at: pathRef),
            args.count == 1,
            case .refArgDot(let s) = arena.node(at: args[0])
        else {
            Issue.record("expected ref with one dot arg")
            return
        }
        #expect(arena.string(s) == "input")
    }

    @Test
    func packageKeywordIsNotIdentifierPrefix() {
        // `packaged` should fail because no `package` keyword is present.
        let result = Parser.parse(source: sourceFile("packaged foo"))
        guard case .failure = result else {
            Issue.record("expected failure on `packaged`")
            return
        }
    }
}
