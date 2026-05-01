import AST
import Foundation
import Rego

func relPath(_ path: String) -> URL {
    let resourcesURL = Bundle.module.resourceURL!
    return resourcesURL.appending(path: path)
}

public func makeExampleBundle(
    manifest: OPA.Manifest? = nil,
    planFiles: [BundleFile]? = nil,
    regoFiles: [BundleFile]? = nil,
    data: AST.RegoValue? = nil
) throws -> OPA.Bundle {
    let id = UUID().uuidString
    let manifest = manifest ?? OPA.Manifest(revision: UUID().uuidString, roots: ["/\(id)"])
    let planFiles =
        planFiles ?? [
            Rego.BundleFile(
                url: URL(string: "/plan.json")!,
                data: #"""
                    {
                    "static":{"strings":[{"value":"result"},{"value":"1"}],"files":[{"value":"bar.rego"}]},
                    "plans":{"plans":[{"name":"foo/hello","blocks":[{"stmts":[
                    {"type":"CallStmt","stmt":{"func":"g0.data.foo.hello","args":[{"type":"local","value":0},{"type":"local","value":1}],"result":2,"file":0,"col":0,"row":0}},
                    {"type":"AssignVarStmt","stmt":{"source":{"type":"local","value":2},"target":3,"file":0,"col":0,"row":0}},
                    {"type":"MakeObjectStmt","stmt":{"target":4,"file":0,"col":0,"row":0}},
                    {"type":"ObjectInsertStmt","stmt":{"key":{"type":"string_index","value":0},"value":{"type":"local","value":3},"object":4,"file":0,"col":0,"row":0}},
                    {"type":"ResultSetAddStmt","stmt":{"value":4,"file":0,"col":0,"row":0}}]}]}]},
                    "funcs":{"funcs":[{"name":"g0.data.foo.hello","params":[0,1],"return":2,"blocks":[{"stmts":[{"type":"ResetLocalStmt","stmt":{"target":3,"file":0,"col":1,"row":3}},{"type":"MakeNumberRefStmt","stmt":{"Index":1,"target":4,"file":0,"col":1,"row":3}},{"type":"AssignVarOnceStmt","stmt":{"source":{"type":"local","value":4},"target":3,"file":0,"col":1,"row":3}}]},{"stmts":[{"type":"IsDefinedStmt","stmt":{"source":3,"file":0,"col":1,"row":3}},{"type":"AssignVarOnceStmt","stmt":{"source":{"type":"local","value":3},"target":2,"file":0,"col":1,"row":3}}]},{"stmts":[{"type":"ReturnLocalStmt","stmt":{"source":2,"file":0,"col":1,"row":3}}]}],"path":["g0","foo","hello"]}]}
                    }
                    """#.data(using: .utf8)!
            )
        ]
    let regoFiles =
        regoFiles ?? [
            Rego.BundleFile(
                url: URL(string: "/\(id)/foo/bar.rego")!,
                data: "package foo\n\nhello=1".data(using: .utf8)!
            )
        ]
    let data =
        data ?? [
            "\(id)": [
                "foo": [
                    "bar": 1,
                    "baz": "qux",
                ]
            ]
        ]
    return try OPA.Bundle(manifest: manifest, planFiles: planFiles, regoFiles: regoFiles, data: data)
}
