//
//  PrinterTests.swift
//  Round-trip printer coverage.
//
//  Two layered test styles:
//
//   - **Golden tests** lock in the canonical formatting choices. Small,
//     stable set — change them only when intentionally evolving the format.
//   - **Idempotency tests** parse a source, print it, re-parse the print
//     output, and assert the second print matches the first. Catches
//     printer bugs (unparseable output, formatting drift) without coupling
//     to a specific golden string.
//
//  A single non-parameterised corpus test re-runs idempotency over every
//  module in the v1 compliance corpus.
//

import Foundation
import Testing

@testable import Parser

@Suite
struct PrinterTests {
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

    // MARK: - Golden output

    /// Canonical-form expectations. These nail down the specific formatting
    /// choices: blank line after package, multi-line brace bodies indented
    /// with `\t`, single-literal bodies inlined, etc.
    static let goldenCases: [(name: String, input: String, expected: String)] = [
        (
            name: "package only",
            input: "package x",
            expected: "package x"
        ),
        (
            name: "package + simple constant",
            input: "package x\npi := 3.14",
            expected: "package x\n\npi := 3.14"
        ),
        (
            name: "default rule",
            input: "package x\ndefault allow := false",
            expected: "package x\n\ndefault allow := false"
        ),
        (
            name: "single-literal body inlined",
            input: "package x\nallow if user == \"admin\"",
            expected: "package x\n\nallow if user == \"admin\""
        ),
        (
            name: "multi-literal body uses brace",
            input: "package x\nallow if { a == 1; b == 2 }",
            expected: "package x\n\nallow if {\n\ta == 1\n\tb == 2\n}"
        ),
        (
            name: "function rule",
            input: "package x\nadd(a, b) := a + b if true",
            expected: "package x\n\nadd(a, b) := a + b if true"
        ),
        (
            name: "set head with contains",
            input: "package x\nadmins contains \"alice\" if true",
            expected: "package x\n\nadmins contains \"alice\" if true"
        ),
        (
            name: "imports separated by single newline",
            input: "package x\nimport data.foo\nimport data.bar as b\nallow if true",
            expected: "package x\n\nimport data.foo\nimport data.bar as b\n\nallow if true"
        ),
        (
            name: "else chain",
            input: "package x\na := 1 if cond1 else := 2 if cond2 else := 3",
            expected: "package x\n\na := 1 if cond1 else := 2 if cond2 else := 3"
        ),
        (
            name: "ref-head with brackets",
            input: "package x\np.allow[action] := true if action == \"read\"",
            expected: "package x\n\np.allow[action] := true if action == \"read\""
        ),
        (
            name: "object comprehension as body",
            input: "package x\nf(x) := x if {y: i | y := [\"a\", \"b\"][i]}",
            expected: "package x\n\nf(x) := x if {y: i | y := [\"a\", \"b\"][i]}"
        ),
        (
            name: "empty set",
            input: "package x\nemptyset := set()",
            expected: "package x\n\nemptyset := set()"
        ),
    ]

    @Test("golden output", arguments: goldenCases)
    func goldenOutput(c: (name: String, input: String, expected: String)) throws {
        guard let printed = Self.format(c.input) else {
            Issue.record("[\(c.name)] parse failed for input: \(c.input)")
            return
        }
        #expect(printed == c.expected, "[\(c.name)] formatted output mismatch")
    }

    // MARK: - Round-trip idempotency

    /// Sources covering each grammar feature. The assertion is that a
    /// second print of the parsed first print equals the first print.
    static let idempotencyCases: [String] = [
        // Basic constructs
        "package x",
        "package x.y.z",
        "package x\n\nimport data.foo",
        "package x\n\nimport data.foo as f",
        "package x\n\npi := 3.14",
        "package x\n\nallow := true",
        "package x\n\ndefault allow := false",

        // Bodies & ifs
        "package x\n\nallow if true",
        "package x\n\nallow if user == \"admin\"",
        "package x\n\nallow if { a == 1; b == 2 }",
        "package x\n\nallow if {\n\ta == 1\n\tb == 2\n}",
        "package x\n\nf(a, b) := a + b if true",
        "package x\n\nadmins contains \"alice\" if user.role == \"admin\"",
        "package x\n\np[id] := info if user_data[id]",
        "package x\n\np.allow[action][resource] := result if cond",

        // Else
        "package x\n\na := 1 if cond1 else := 2 if cond2 else := 3",
        "package x\n\na := 1 if cond1 else { y == 1 }",

        // Expressions
        "package x\n\np if a + b * c == 7",
        "package x\n\np if (a + b) * c == 6",
        "package x\n\np if a and b or c",
        "package x\n\np if a or b and c",
        "package x\n\np if (a or b) and c",
        "package x\n\np if -x == -1",
        "package x\n\np if not user.banned",
        "package x\n\np if not { a == 1; b == 2 }",

        // Composites
        "package x\n\nx := [1, 2, 3]",
        "package x\n\nx := {\"a\": 1, \"b\": 2}",
        "package x\n\nx := {1, 2, 3}",
        "package x\n\nx := set()",
        "package x\n\nx := []",
        "package x\n\nx := {}",

        // Comprehensions
        "package x\n\nx := [n | n := input.numbers[_]; n > 0]",
        "package x\n\nx := {n | n := input.numbers[_]}",
        "package x\n\nx := {k: v | some k, v in input.obj}",

        // some / every
        "package x\n\np if some x in input.xs",
        "package x\n\np if some k, v in input.obj",
        "package x\n\np if some \"foo\" in input.xs",
        "package x\n\np if some {\"k\": v} in input.xs",
        "package x\n\np if { some x; x == 1 }",
        "package x\n\np if every x in input.xs { x > 0 }",
        "package x\n\np if every k, v in input.obj { v > 0 }",

        // Membership
        "package x\n\np if 1 in [1, 2, 3]",
        "package x\n\np if (1, \"two\" in [\"one\", \"two\"])",

        // With modifiers
        "package x\n\nq := r if { r := input.x with input.x as 42 }",
        "package x\n\nq if { allow with input.a as 1 with input.b as 2 }",

        // Strings & numbers
        "package x\n\ngreeting := \"hello\\nworld\"",
        "package x\n\ngreeting := `raw\nstring`",
        "package x\n\nnums := [-1, 0, 1, 1.5, 2e10]",
        "package x\n\nflags := [true, false, null]",

        // Templates
        "package x\n\ngreeting := $\"hello {name}\"",
        "package x\n\ngreeting := $`raw {name} string`",

        // Reserved-word ref heads
        "package x\n\nnull.foo := 1",
        "package x\n\nelse.foo := 2",
        "package x\n\nwith.bar(y) := y if true",
        "package x\n\np if else.foo == 1",
        "package x\n\np if foo.if == 2",

        // Function calls
        "package x\n\np := count(input.xs)",
        "package x\n\np := f(g(x), h(y, z))",

        // Nested everything
        "package x\n\nallow if {\n\tinput.user.role == \"admin\"\n\tnot input.user.banned\n\tsome r in input.user.resources\n\tcount(r.permissions) > 0\n}",
    ]

    @Test("round-trip idempotency", arguments: idempotencyCases)
    func roundTripIdempotent(src: String) throws {
        guard let first = Self.format(src) else {
            Issue.record("first parse failed: \(src.prefix(60))…")
            return
        }
        guard let second = Self.format(first) else {
            Issue.record("re-parse of printed output failed:\noutput: \(first)")
            return
        }
        #expect(first == second, "round-trip not idempotent\n  first:  \(first)\n  second: \(second)")
    }

    // MARK: - Specific formatting decisions

    @Test
    func emptyArenaPrintsEmpty() throws {
        let arena = SyntaxArena(
            source: SourceFile(
                url: URL(fileURLWithPath: "x.rego"), bundleID: nil, contents: ""))
        #expect(Printer(arena: arena).print() == "")
    }

    @Test
    func stringEscapesAreReversed() throws {
        // Parser decodes `\n` to a real newline; printer must re-escape.
        guard let printed = Self.format("package x\n\ng := \"a\\nb\\tc\\\\d\"") else {
            Issue.record("parse failed")
            return
        }
        #expect(printed.contains("\"a\\nb\\tc\\\\d\""))
    }

    @Test
    func parensPreservedFromSource() throws {
        guard let printed = Self.format("package x\n\np := (a + b) * c") else {
            Issue.record("parse failed")
            return
        }
        #expect(printed.contains("(a + b) * c"))
    }

    @Test
    func precedenceParensInsertedWhenNeeded() throws {
        // Manually build an AST where the binary tree disagrees with
        // operator precedence and assert the printer adds parens.
        let src = "package x"
        let source = SourceFile(
            url: URL(fileURLWithPath: "test.rego"), bundleID: nil, contents: src)
        let arena = SyntaxArena(source: source)
        let aIdx = arena.intern("a")
        let bIdx = arena.intern("b")
        let cIdx = arena.intern("c")
        let aRef = arena.add(.variable(aIdx), span: .empty)
        let bRef = arena.add(.variable(bIdx), span: .empty)
        let cRef = arena.add(.variable(cIdx), span: .empty)
        let aPlusB = arena.add(.binary(op: .add, lhs: aRef, rhs: bRef), span: .empty)
        // (a + b) * c — written as a tree with `*` enclosing `+`.
        let mul = arena.add(.binary(op: .mul, lhs: aPlusB, rhs: cRef), span: .empty)
        let printed = Printer(arena: arena).print(mul)
        #expect(printed == "(a + b) * c", "got: \(printed)")
    }

    // MARK: - Corpus round-trip

    /// Resolve the compliance corpus directory (mirrors `CorpusTests`).
    private static func corpusURL(file: String = #filePath) -> URL? {
        let here = URL(fileURLWithPath: file)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let corpus = root.appendingPathComponent("ComplianceSuite")
            .appendingPathComponent("Tests")
            .appendingPathComponent("RegoComplianceTests")
            .appendingPathComponent("TestData")
            .appendingPathComponent("v1")
        return FileManager.default.fileExists(atPath: corpus.path) ? corpus : nil
    }

    private struct CaseFile: Decodable {
        let cases: [Case]
        struct Case: Decodable {
            let note: String?
            let modules: [String]?
        }
    }

    @Test
    func roundTripsComplianceCorpus() throws {
        guard let corpus = Self.corpusURL() else { return }
        let fm = FileManager.default
        guard
            let enumerator = fm.enumerator(
                at: corpus, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return }

        var totalModules = 0
        var idempotent = 0
        var examples: [(file: String, note: String, first: String, second: String)] = []
        let decoder = JSONDecoder()

        for case let url as URL in enumerator where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                let parsed = try? decoder.decode(CaseFile.self, from: data)
            else { continue }
            for c in parsed.cases {
                guard let modules = c.modules else { continue }
                for module in modules {
                    totalModules += 1
                    guard let first = Self.format(module) else { continue }
                    guard let second = Self.format(first) else {
                        if examples.count < 5 {
                            examples.append(
                                (
                                    url.lastPathComponent, c.note ?? "", first,
                                    "<reparse failed>"
                                ))
                        }
                        continue
                    }
                    if first == second {
                        idempotent += 1
                    } else if examples.count < 5 {
                        examples.append((url.lastPathComponent, c.note ?? "", first, second))
                    }
                }
            }
        }

        let pct =
            totalModules == 0
            ? "—" : String(format: "%.2f%%", 100.0 * Double(idempotent) / Double(totalModules))
        Swift.print(
            "[printer corpus] modules=\(totalModules) idempotent=\(idempotent) (\(pct))")
        for ex in examples {
            Swift.print("[printer corpus]   ex: \(ex.file) :: \(ex.note)")
            Swift.print("                       first:  \(ex.first.prefix(120))")
            Swift.print("                       second: \(ex.second.prefix(120))")
        }

        #expect(idempotent == totalModules)
    }
}
