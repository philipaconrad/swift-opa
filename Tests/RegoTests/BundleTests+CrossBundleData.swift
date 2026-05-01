import AST
import Foundation
import Testing

@testable import Rego

@Suite("BundleTests - Cross Bundle Data")
struct BundleCrossBundleDataTests {

    /// Builds a bundle that contains a plan referencing `data.<dataPath>` and
    /// returning it as the result of the given decision. The bundle itself
    /// contains NO data - the data is expected to come from a different bundle.
    static func makePolicyOnlyBundle(
        decisionPath: String,
        dataPath: String,
        bundleName: String = "custom_policy"
    ) throws -> OPA.Bundle {
        let revID = UUID().uuidString
        // The policy bundle "owns" the decision path root, but NOT the data path root.
        // This way the data can be provided by a separate bundle.
        let roots = [decisionPath]
        let manifest = OPA.Manifest(revision: revID, roots: roots)

        let segments = dataPath.split(separator: "/").map(String.init)

        // Build static strings:
        //   index 0: "result" (object key for the result set).
        //   indices 1..n: each path segment used as a DotStmt key.
        var staticStrings: [String] = [#"{"value": "result"}"#]
        for segment in segments {
            staticStrings.append(#"{"value": "\#(segment)"}"#)
        }

        // Local 0: input, Local 1: data (per IR convention)
        // Walk data via DotStmts, starting from local 1 (data root).
        var stmts: [String] = []
        var sourceLocalIdx = 1  // start at data root
        var keyStrIdx = 1
        var targetLocalIdx = 5
        for _ in segments {
            let dotStmt = #"""
                {"type":"DotStmt","stmt":{"source":{"type":"local","value":\#(sourceLocalIdx)},"key":{"type":"string_index","value":\#(keyStrIdx)},"target":\#(targetLocalIdx),"file":0,"col":0,"row":0}}
                """#
            stmts.append(dotStmt)
            sourceLocalIdx = targetLocalIdx
            keyStrIdx += 1
            targetLocalIdx += 1
        }

        // Assign final walked value to target local 2, then construct result object
        stmts.append(
            #"{"type":"AssignVarStmt","stmt":{"source":{"type":"local","value":\#(sourceLocalIdx)},"target":2,"file":0,"col":0,"row":0}}"#
        )
        stmts.append(
            #"{"type":"MakeObjectStmt","stmt":{"target":4,"file":0,"col":0,"row":0}}"#
        )
        stmts.append(
            #"{"type":"ObjectInsertStmt","stmt":{"key":{"type":"string_index","value":0},"value":{"type":"local","value":2},"object":4,"file":0,"col":0,"row":0}}"#
        )
        stmts.append(
            #"{"type":"ResultSetAddStmt","stmt":{"value":4,"file":0,"col":0,"row":0}}"#
        )

        let planJSON = """
            {
                "static":{"strings":[\(staticStrings.joined(separator: ","))],"files":[{"value":"policy.rego"}]},
                "plans":{"plans":[{"name":"\(decisionPath)","blocks":[{"stmts":[\(stmts.joined(separator: ","))]}]}]},
                "funcs":{"funcs":[]}
            }
            """

        return try makeExampleBundle(
            manifest: manifest,
            planFiles: [
                Rego.BundleFile(
                    url: URL(string: "/\(bundleName)/plan.json")!,
                    data: planJSON.data(using: .utf8)!
                )
            ],
            regoFiles: [],
            // Explicitly no data! This bundle only ships the plan.
            data: .object([:])
        )
    }

    /// Builds a bundle that contains ONLY data at a given path - no plans, no rego.
    static func makeDataOnlyBundle(
        dataPath: String,
        value: AST.RegoValue,
        bundleName: String = "custom_data"
    ) throws -> OPA.Bundle {
        let segments = dataPath.split(separator: "/").map(String.init)

        // Nest the value under each path segment
        var nested: AST.RegoValue = value
        for segment in segments.reversed() {
            nested = .object([.string(segment): nested])
        }

        // The data bundle owns the data path root.
        let roots = [segments.joined(separator: "/")]
        let manifest = OPA.Manifest(revision: UUID().uuidString, roots: roots)

        return try makeExampleBundle(
            manifest: manifest,
            planFiles: [],
            regoFiles: [],
            data: nested
        )
    }

    @Test("Policy bundle can reference data from a separate data-only bundle")
    func testCrossBundleDataReference() async throws {
        let decisionPath = "example/allow"
        let dataPath = "config/example/value"

        let policyBundle = try Self.makePolicyOnlyBundle(
            decisionPath: decisionPath,
            dataPath: dataPath
        )

        let dataBundle = try Self.makeDataOnlyBundle(
            dataPath: dataPath,
            value: .number(5)
        )

        var engine = OPA.Engine(bundles: [
            "custom_policy": policyBundle,
            "custom_data": dataBundle,
        ])
        let pq = try await engine.prepareForEvaluation(query: "data/" + decisionPath)

        let result = try await pq.evaluate(
            input: .object([:])
        )

        let expected: AST.RegoValue = .object(["result": 5])
        #expect(result == ResultSet([expected]))
    }

    @Test("Policy bundle evaluation fails when data bundle is missing")
    func testMissingDataBundleFails() async throws {
        let decisionPath = "example/allow"
        let dataPath = "config/feature/enabled"

        let policyBundle = try Self.makePolicyOnlyBundle(
            decisionPath: decisionPath,
            dataPath: dataPath
        )

        // Only register the policy bundle - no data bundle.
        var engine = OPA.Engine(bundles: ["policy": policyBundle])
        let pq = try await engine.prepareForEvaluation(query: "data/" + decisionPath)
        let result = try await pq.evaluate(
            input: .object([:])
        )

        #expect(result == ResultSet([]))  // Policy fails at runtime, returning undefined.
    }

    @Test("Bundle validation rejects data outside of declared roots")
    func testBundleCannotWriteOutsideRoots() async throws {
        // Data bundle declares root "config/example/value" but also happens
        // to have data at `other/path`. Only the declared root's subtree
        // should make it into the store.
        let decisionPath = "example/allow"
        let dataPath = "config/example/value"

        let policyBundle = try Self.makePolicyOnlyBundle(
            decisionPath: decisionPath, dataPath: dataPath
        )

        // Craft a data bundle whose bundle.data has extra keys outside its roots.
        let segments = dataPath.split(separator: "/").map(String.init)
        var nested: AST.RegoValue = .number(42)
        for segment in segments.reversed() {
            nested = .object([.string(segment): nested])
        }
        // Merge in an out-of-root key that should NOT end up in the store:
        if case .object(var obj) = nested {
            obj[.string("sneaky")] = .string("should-not-appear")
            nested = .object(obj)
        }
        let manifest = OPA.Manifest(
            revision: UUID().uuidString,
            roots: [dataPath]
        )
        let dataBundle = try makeExampleBundle(
            manifest: manifest, planFiles: [], regoFiles: [], data: nested
        )

        var engine = OPA.Engine(bundles: [
            "custom_policy": policyBundle,
            "custom_data": dataBundle,
        ])

        await #expect(throws: RegoError.self) {
            _ = try await engine.prepareForEvaluation(query: "data/" + decisionPath)
        }
    }

    @Test("Policy can query a prefix that merges data from sibling data bundles")
    func testPrefixQueryAcrossSiblingDataBundles() async throws {
        let decisionPath = "example/features"
        let prefixPath = "config/features"

        // Policy walks data.config.features - a prefix shared by both data
        // bundles' roots - and returns the resulting object.
        let policyBundle = try Self.makePolicyOnlyBundle(
            decisionPath: decisionPath,
            dataPath: prefixPath
        )

        // Two sibling data bundles, each owning a disjoint leaf under
        // config/features. The engine should write each bundle's subtree
        // at ["data", "config", "features", "<leaf>"], leaving the
        // intermediate {config: {features: {...}}} branch shared.
        let dataBundleA = try Self.makeDataOnlyBundle(
            dataPath: "\(prefixPath)/a",
            value: .string("alpha")
        )
        let dataBundleB = try Self.makeDataOnlyBundle(
            dataPath: "\(prefixPath)/b",
            value: .string("beta")
        )

        var engine = OPA.Engine(bundles: [
            "policy": policyBundle,
            "data_a": dataBundleA,
            "data_b": dataBundleB,
        ])
        let pq = try await engine.prepareForEvaluation(query: "data/" + decisionPath)
        let result = try await pq.evaluate(input: .object([:]))

        // Reading the prefix should produce an object containing both
        // siblings' contributions.
        let expected: AST.RegoValue = .object([
            "result": .object([
                "a": .string("alpha"),
                "b": .string("beta"),
            ])
        ])
        #expect(result == ResultSet([expected]))
    }
}
