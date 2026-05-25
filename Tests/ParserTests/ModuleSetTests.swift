//
//  ModuleSetTests.swift
//  Phase 8 — workspace API: incremental add, package index, visitor,
//  mutation, name-resolution scaffolding.
//

import Foundation
import Testing

@testable import Parser

@Suite
struct ParserPhase8ModuleSetTests {
    private func source(_ name: String, _ contents: String) -> SourceFile {
        SourceFile(url: URL(fileURLWithPath: name), bundleID: nil, contents: contents)
    }

    // MARK: ModuleSet.add — incremental

    @Test
    func addReturnsArenaID() throws {
        let ms = ModuleSet()
        let res = ms.add(source("a.rego", "package foo"))
        guard case .success(let id) = res else {
            Issue.record("add failed: \(res)")
            return
        }
        #expect(ms.arenas[id] != nil)
    }

    @Test
    func addSameContentReturnsSameID() throws {
        let ms = ModuleSet()
        guard case .success(let id1) = ms.add(source("a.rego", "package foo")) else {
            Issue.record("first add failed")
            return
        }
        guard case .success(let id2) = ms.add(source("a.rego", "package foo")) else {
            Issue.record("second add failed")
            return
        }
        #expect(id1 == id2)
        #expect(ms.arenas.count == 1)
    }

    @Test
    func addChangedContentReplacesOldArena() throws {
        let ms = ModuleSet()
        guard case .success(let id1) = ms.add(source("a.rego", "package foo")) else {
            Issue.record("first add failed")
            return
        }
        guard case .success(let id2) = ms.add(source("a.rego", "package bar")) else {
            Issue.record("second add failed")
            return
        }
        #expect(id1 != id2)
        #expect(ms.arenas.count == 1)
        #expect(ms.arenas[id2] != nil)
    }

    @Test
    func addParseFailureReturnsFailure() throws {
        let ms = ModuleSet()
        let res = ms.add(source("a.rego", "package "))  // missing path
        guard case .failure = res else {
            Issue.record("expected failure for malformed source")
            return
        }
        #expect(ms.arenas.isEmpty)
    }

    // MARK: Package index

    @Test
    func arenasForPackageReturnsAllMatches() throws {
        let ms = ModuleSet()
        _ = ms.add(source("a.rego", "package x.y\n\na := 1"))
        _ = ms.add(source("b.rego", "package x.y\n\nb := 2"))
        _ = ms.add(source("c.rego", "package other\n\nc := 3"))
        #expect(ms.arenas(forPackage: "x.y").count == 2)
        #expect(ms.arenas(forPackage: "other").count == 1)
        #expect(ms.arenas(forPackage: "missing").isEmpty)
    }

    @Test
    func removeEvictsFromPackageIndex() throws {
        let ms = ModuleSet()
        guard case .success(let id) = ms.add(source("a.rego", "package x")) else {
            Issue.record("add failed")
            return
        }
        ms.remove(id)
        #expect(ms.arenas.isEmpty)
        #expect(ms.arenas(forPackage: "x").isEmpty)
    }

    // MARK: Visitor / children

    @Test
    func walkVisitsAllNodes() throws {
        let src = "package x\n\nallow if user == \"admin\""
        guard case .success(let arena) = Parser.parse(source: source("a.rego", src)),
            let root = arena.root
        else {
            Issue.record("parse failed")
            return
        }
        var count = 0
        arena.walk(from: root) { _ in count += 1 }
        #expect(count > 1)
        #expect(count == arena.nodes.count)
    }

    @Test
    func childrenOfModuleIncludesPackageImportsRules() throws {
        let src = """
            package x

            import data.foo
            import data.bar

            a := 1
            b := 2
            """
        guard case .success(let arena) = Parser.parse(source: source("a.rego", src)),
            let root = arena.root
        else {
            Issue.record("parse failed")
            return
        }
        let kids = arena.children(of: root)
        // 1 package + 2 imports + 2 rules = 5.
        #expect(kids.count == 5)
    }

    // MARK: Mutation

    @Test
    func replaceUpdatesNode() throws {
        let arena = SyntaxArena(source: source("a.rego", "x"))
        let idx = arena.intern("x")
        let ref = arena.add(.variable(idx), span: .empty)
        let newIdx = arena.intern("y")
        arena.replace(ref, with: .variable(newIdx))
        guard case .variable(let stored) = arena.node(at: ref) else {
            Issue.record("expected variable")
            return
        }
        #expect(stored == newIdx)
    }

    // MARK: NameResolution

    @Test
    func nameResolutionCollectsRulesByPackage() throws {
        let ms = ModuleSet()
        _ = ms.add(source("a.rego", "package data.example\n\nallow := true\ndeny := false"))
        _ = ms.add(source("b.rego", "package data.other\n\npi := 3.14"))
        let nr = NameResolution(ms)
        nr.rebuild()
        #expect(nr.packageBindings["data.example"]?.count == 2)
        #expect(nr.packageBindings["data.other"]?.count == 1)
    }

    @Test
    func nameResolutionResolvesRefPath() throws {
        let ms = ModuleSet()
        _ = ms.add(source("a.rego", "package data.example\n\nallow := true"))
        let nr = NameResolution(ms)
        nr.rebuild()
        let bindings = nr.resolve(refPath: ["data", "example", "allow"])
        #expect(bindings.count == 1)
        #expect(bindings.first?.name == "allow")
    }

    @Test
    func nameResolutionResolveMissingReturnsEmpty() throws {
        let ms = ModuleSet()
        _ = ms.add(source("a.rego", "package data.example\n\nallow := true"))
        let nr = NameResolution(ms)
        nr.rebuild()
        #expect(nr.resolve(refPath: ["data", "missing", "x"]).isEmpty)
    }
}
