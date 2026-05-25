//
//  CorpusTests.swift
//  Phase 9 — exercise the parser over the compliance test corpus.
//
//  The compliance test JSON files live in `ComplianceSuite/Tests/.../TestData`
//  and embed Rego policy text inside a `modules: [String]` array per case.
//  This test extracts those policies, parses each, and asserts every one
//  parses cleanly. The summary print stays so regressions surface a
//  diagnostic alongside the assertion failure.
//

import Foundation
import Testing

@testable import Parser

@Suite
struct ParserPhase9CorpusTests {

    /// Resolve the compliance corpus directory relative to this source file.
    /// `#filePath` points at this file's path on disk; the corpus sits at
    /// `../../../ComplianceSuite/Tests/RegoComplianceTests/TestData/v1`.
    private static func corpusURL(file: String = #filePath) -> URL? {
        let here = URL(fileURLWithPath: file)
        let root = here.deletingLastPathComponent()  // ParserTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // <repo>/
        let corpus =
            root
            .appendingPathComponent("ComplianceSuite")
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
    func parsesComplianceCorpus() throws {
        guard let corpus = Self.corpusURL() else {
            // Compliance corpus not present in this checkout — skip.
            return
        }

        let fm = FileManager.default
        guard
            let enumerator = fm.enumerator(
                at: corpus,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else { return }

        var totalCases = 0
        var totalModules = 0
        var passed = 0
        var failures: [(file: String, note: String, message: String, snippet: String)] = []
        var kindHistogram: [String: Int] = [:]

        let decoder = JSONDecoder()
        for case let url as URL in enumerator where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                let parsed = try? decoder.decode(CaseFile.self, from: data)
            else { continue }
            for c in parsed.cases {
                totalCases += 1
                guard let modules = c.modules else { continue }
                for module in modules {
                    totalModules += 1
                    let source = SourceFile(url: url, bundleID: nil, contents: module)
                    switch Parser.parse(source: source) {
                    case .success:
                        passed += 1
                    case .failure(let errs):
                        let kind = errs.first.map { kindLabel($0.kind) } ?? "unknown"
                        kindHistogram[kind, default: 0] += 1
                        if failures.count < 60 {
                            // Pull a 60-char window around the error span.
                            let snippet: String = {
                                guard let span = errs.first?.span else { return "" }
                                let lines = module.split(
                                    separator: "\n", omittingEmptySubsequences: false)
                                let lineIdx = Int(span.start.line) - 1
                                if lineIdx >= 0 && lineIdx < lines.count {
                                    return String(lines[lineIdx])
                                }
                                return ""
                            }()
                            failures.append(
                                (
                                    file: url.lastPathComponent,
                                    note: c.note ?? "",
                                    message: errs.first?.message ?? "?",
                                    snippet: snippet
                                ))
                        }
                    }
                }
            }
        }

        // Print a summary so the developer can see corpus health locally.
        // Always fits on a few lines — does NOT fail the test.
        let pct =
            totalModules == 0
            ? "—"
            : String(format: "%.1f%%", 100.0 * Double(passed) / Double(totalModules))
        print("[parser corpus] cases=\(totalCases) modules=\(totalModules) pass=\(passed) (\(pct))")
        if !kindHistogram.isEmpty {
            let top = kindHistogram.sorted { $0.value > $1.value }.prefix(8)
            for (k, v) in top {
                print("[parser corpus]   \(v.description.padding(toLength: 6, withPad: " ", startingAt: 0))\(k)")
            }
        }
        for f in failures.prefix(40) {
            print(
                "[parser corpus]   ex: \(f.file) :: \(f.note)\n"
                    + "                       msg: \(f.message)\n"
                    + "                       at:  \(f.snippet)")
        }

        // Sanity: the corpus is non-empty if the directory exists.
        #expect(totalModules > 0)
        // Guard against regressions: every module in the v1 corpus must
        // parse. Failures above are printed for diagnostics.
        #expect(passed == totalModules)
    }

    private func kindLabel(_ kind: ParseError.Kind) -> String {
        switch kind {
        case .expected: return "expected"
        case .unexpected: return "unexpected"
        case .reservedWord: return "reservedWord"
        case .invalidNumber: return "invalidNumber"
        case .invalidString: return "invalidString"
        case .unterminatedString: return "unterminatedString"
        case .unterminatedRawString: return "unterminatedRawString"
        case .missingPackage: return "missingPackage"
        case .unsupportedSyntax: return "unsupportedSyntax"
        case .other(let s): return "other(\(s))"
        }
    }
}
