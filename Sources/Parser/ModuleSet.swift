//
//  ModuleSet.swift
//  Parser - workspace-level API for collections of parsed files plus
//  scaffolding for cross-file name resolution.
//
//  This sits one level above `SyntaxArena`: a `ModuleSet` owns many arenas
//  (one per file), supports content-equality-based incremental updates, and
//  exposes a package → arenas index. `NameResolution` builds a flat global
//  symbol table by walking arenas; full per-expression name binding is a
//  follow-up that will live alongside type/data-flow passes.
//

import Foundation

/// A collection of parsed files that should be analysed together.
///
/// Re-adding the same `SourceFile` (same URL, same contents) is a no-op and
/// returns the existing `ArenaID`. Adding the same URL with different
/// contents replaces the previous arena. Removing a file evicts it from the
/// per-package index.
public final class ModuleSet {
    public private(set) var arenas: [ArenaID: SyntaxArena] = [:]
    private var byURL: [URL: ArenaID] = [:]
    private var byPackagePath: [String: [ArenaID]] = [:]
    private var nextID: UInt32 = 0

    public init() {}

    /// Add or update a parsed file. If `source` matches an existing entry's
    /// URL *and* contents, the existing `ArenaID` is returned without
    /// reparsing; otherwise the file is parsed fresh.
    @discardableResult
    public func add(_ source: SourceFile) -> Result<ArenaID, ParseErrors> {
        if let existingID = byURL[source.url],
            let existing = arenas[existingID],
            existing.source.contents == source.contents
        {
            return .success(existingID)
        }
        switch Parser.parse(source: source) {
        case .success(let arena):
            if let oldID = byURL[source.url] {
                _ = remove(oldID)
            }
            let id = ArenaID(raw: nextID)
            nextID += 1
            arenas[id] = arena
            byURL[source.url] = id
            if let pkg = ModuleSet.packagePath(of: arena) {
                byPackagePath[pkg, default: []].append(id)
            }
            return .success(id)
        case .failure(let errs):
            return .failure(errs)
        }
    }

    /// Remove the arena identified by `id` from the set. Returns the removed
    /// arena, or `nil` if `id` is not present.
    @discardableResult
    public func remove(_ id: ArenaID) -> SyntaxArena? {
        guard let arena = arenas.removeValue(forKey: id) else { return nil }
        byURL.removeValue(forKey: arena.source.url)
        if let pkg = ModuleSet.packagePath(of: arena) {
            byPackagePath[pkg]?.removeAll { $0 == id }
            if byPackagePath[pkg]?.isEmpty == true {
                byPackagePath.removeValue(forKey: pkg)
            }
        }
        return arena
    }

    /// All arenas in the set, in insertion-id order.
    public func allArenas() -> [SyntaxArena] {
        arenas.keys.sorted { $0.raw < $1.raw }.compactMap { arenas[$0] }
    }

    /// Arenas whose `package` declaration matches `path` (e.g.
    /// `"data.example.foo"`).
    public func arenas(forPackage path: String) -> [SyntaxArena] {
        (byPackagePath[path] ?? []).compactMap { arenas[$0] }
    }

    /// Resolve a parsed `package` declaration to its dotted-path string.
    /// Currently the package head must be a simple `var { "." ident }` ref.
    static func packagePath(of arena: SyntaxArena) -> String? {
        guard let root = arena.root,
            case .module(let pkgRef, _, _) = arena.node(at: root),
            case .packageDecl(let refRef) = arena.node(at: pkgRef)
        else { return nil }
        return refToDottedPath(refRef, arena: arena)
    }

    /// Convert a `ref` node consisting of a `variable` head and `refArgDot`
    /// args into a dotted-path string. Returns `nil` if the ref contains
    /// any non-dot arg.
    static func refToDottedPath(_ ref: NodeRef, arena: SyntaxArena) -> String? {
        guard case .ref(let head, let args) = arena.node(at: ref),
            case .variable(let headIdx) = arena.node(at: head)
        else { return nil }
        var parts: [String] = [arena.string(headIdx)]
        for arg in args {
            guard case .refArgDot(let idx) = arena.node(at: arg) else { return nil }
            parts.append(arena.string(idx))
        }
        return parts.joined(separator: ".")
    }
}

/// A single name introduced by a rule head, identified by the (arena, head)
/// pair so callers can navigate back to the source declaration.
public struct NameBinding: Hashable, Sendable {
    public let name: String
    public let arenaID: ArenaID
    /// `NodeRef` of the rule head.
    public let headRef: NodeRef

    public init(name: String, arenaID: ArenaID, headRef: NodeRef) {
        self.name = name
        self.arenaID = arenaID
        self.headRef = headRef
    }
}

/// Flat global symbol table keyed by package path. Phase 8 scaffolding —
/// resolves dotted refs to the rule heads that declare them, but does not
/// (yet) bind variables inside expressions or follow `import` aliases.
public final class NameResolution {
    public let moduleSet: ModuleSet
    /// `package path` → `[NameBinding]`. The `name` of each binding is the
    /// rule head's dotted path *relative to* its package.
    public private(set) var packageBindings: [String: [NameBinding]] = [:]

    public init(_ moduleSet: ModuleSet) {
        self.moduleSet = moduleSet
    }

    /// Walk all arenas and rebuild `packageBindings`. Cheap — proportional
    /// to the number of rule-head nodes across all arenas.
    public func rebuild() {
        packageBindings.removeAll(keepingCapacity: true)
        for (id, arena) in moduleSet.arenas {
            guard let pkg = ModuleSet.packagePath(of: arena),
                let root = arena.root,
                case .module(_, _, let rules) = arena.node(at: root)
            else { continue }
            for rule in rules {
                guard case .rule(_, let head, _, _) = arena.node(at: rule),
                    case .ruleHead(let name, _, _, _) = arena.node(at: head),
                    let dotted = ModuleSet.refToDottedPath(name, arena: arena)
                else { continue }
                let binding = NameBinding(name: dotted, arenaID: id, headRef: head)
                packageBindings[pkg, default: []].append(binding)
            }
        }
    }

    /// Resolve a dotted ref path (e.g. `["data", "example", "allow"]`) to
    /// the rule heads that declare it. Returns an empty array if no rules
    /// match. The path's first segment is expected to be `data`; otherwise
    /// the name is looked up package-relative.
    public func resolve(refPath: [String]) -> [NameBinding] {
        guard !refPath.isEmpty else { return [] }
        // Try splitting at every prefix point: longer package prefix first
        // so a binding like `data.x.y` (package `data.x`, rule `y`) wins
        // over package `data`, rule `x.y`.
        var results: [NameBinding] = []
        for split in (1...refPath.count).reversed() {
            let pkg = refPath[0..<split].joined(separator: ".")
            let name = refPath[split..<refPath.count].joined(separator: ".")
            if let bindings = packageBindings[pkg] {
                results.append(contentsOf: bindings.filter { $0.name == name })
            }
        }
        return results
    }
}
