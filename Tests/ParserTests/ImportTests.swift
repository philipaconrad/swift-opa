//
//  ImportTests.swift
//  Phase 7 — import declarations and module composition.
//

import Foundation
import Testing

@testable import Parser

@Suite
struct ParserPhase7ImportTests {
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

    @Test
    func parsesSimpleImport() throws {
        let f = Fixture("import data.foo")
        let ref = try f.grammar.parseImport(&f.input)
        guard case .importDecl(_, let alias) = f.arena.node(at: ref) else {
            Issue.record("expected importDecl")
            return
        }
        #expect(alias == nil)
    }

    @Test
    func parsesImportWithDottedPath() throws {
        let f = Fixture("import data.foo.bar.baz")
        let ref = try f.grammar.parseImport(&f.input)
        guard case .importDecl(let path, _) = f.arena.node(at: ref) else {
            Issue.record("expected importDecl")
            return
        }
        guard case .ref(_, let args) = f.arena.node(at: path) else {
            Issue.record("expected ref path")
            return
        }
        // head=data, then 3 .foo .bar .baz dot args.
        #expect(args.count == 3)
    }

    @Test
    func parsesImportWithAlias() throws {
        let f = Fixture("import data.foo as f")
        let ref = try f.grammar.parseImport(&f.input)
        guard case .importDecl(_, let alias) = f.arena.node(at: ref) else {
            Issue.record("expected importDecl")
            return
        }
        guard let alias else {
            Issue.record("expected alias")
            return
        }
        #expect(f.arena.string(alias) == "f")
    }

    @Test
    func rejectsImportWithReservedAlias() throws {
        let f = Fixture("import data.foo as if")
        #expect(throws: ParseError.self) {
            try f.grammar.parseImport(&f.input)
        }
    }

    // MARK: Module composition

    @Test
    func parsesModuleWithImports() throws {
        let src = """
            package example

            import data.foo
            import data.bar as b

            allow := true
            """
        let source = SourceFile(url: URL(fileURLWithPath: "ex.rego"), bundleID: nil, contents: src)
        guard case .success(let arena) = Parser.parse(source: source) else {
            Issue.record("parse failed")
            return
        }
        guard let root = arena.root,
            case .module(_, let imports, let rules) = arena.node(at: root)
        else {
            Issue.record("expected module root")
            return
        }
        #expect(imports.count == 2)
        #expect(rules.count == 1)
    }

    @Test
    func parsesPackageOnlyModule() throws {
        let src = "package example"
        let source = SourceFile(url: URL(fileURLWithPath: "ex.rego"), bundleID: nil, contents: src)
        guard case .success(let arena) = Parser.parse(source: source) else {
            Issue.record("parse failed")
            return
        }
        guard let root = arena.root,
            case .module(_, let imports, let rules) = arena.node(at: root)
        else {
            Issue.record("expected module root")
            return
        }
        #expect(imports.isEmpty)
        #expect(rules.isEmpty)
    }
}
