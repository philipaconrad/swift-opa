//
//  CommentBinding.swift
//  Parser - associate free-floating comments with the AST nodes they
//  describe.
//
//  The lexer records every comment in `arena.comments` as it parses, in
//  source order. The binding pass produced by `bindComments` walks those
//  comments alongside a list of "anchor" nodes and assigns each comment
//  to one of:
//
//    - leading(ref)  — on contiguous lines immediately above the node,
//      grouped by blank-line separators so multiple groups can stack;
//    - trailing(ref) — on the same line as the node's syntactic end,
//      after the end (e.g. `x := 1  # explanation`);
//    - freestanding — between top-level constructs, with no immediate
//      neighbour to attach to.
//
//  Anchors are top-level constructs (package, imports, rules) plus
//  literals inside brace-bodied queries (rule body, `every` body, `not
//  { … }`, brace `else`). Comprehension bodies are NOT walked into;
//  preserving comments inside `[x | … ]` is a follow-up.
//
//  `# METADATA` blocks are recognised here too. A leading run whose first
//  comment is exactly `# METADATA` is tagged as a `MetadataBlock`. Per
//  OPA's metadata semantics, METADATA blocks bind to the next anchor
//  even across blank-line gaps; non-METADATA leading runs require the
//  run to end on the line immediately above the anchor.
//

import Foundation

/// Where a comment sits relative to its target node.
public enum CommentPosition: Sendable, Hashable {
    case leading
    case trailing
}

/// Default scope inferred from a metadata target's node kind. The actual
/// `scope:` field inside the YAML can override this — that decoding is
/// not done here.
public enum MetadataScope: String, Sendable, Hashable {
    case rule
    case document
    case package
    case subpackages
}

/// A `# METADATA` annotation block attached to a target node.
public struct MetadataBlock: Sendable, Hashable {
    /// The node this metadata describes (rule, package decl, import).
    public let target: NodeRef
    /// YAML body lines (everything after `# METADATA`), with the leading
    /// `#` and one optional space stripped. One entry per source line.
    /// Decoding the YAML into structured fields is left to callers.
    public let lines: [String]
    /// Default scope based on the target type. Callers are expected to
    /// override this if the YAML body sets `scope:`.
    public let defaultScope: MetadataScope
    /// Source span covering the whole block (the `# METADATA` header
    /// through the final YAML line).
    public let span: SourceSpan

    public init(target: NodeRef, lines: [String], defaultScope: MetadataScope, span: SourceSpan) {
        self.target = target
        self.lines = lines
        self.defaultScope = defaultScope
        self.span = span
    }
}

/// Side-table associating comments with AST nodes. Built once after a
/// successful parse by `bindComments(arena:)` and stored on the arena;
/// rebuild explicitly if the arena is mutated afterwards.
public struct CommentBindings: Sendable {
    /// Leading comment groups per anchor, in source order. Each group is
    /// a contiguous run (no blank-line gap); multiple groups indicate
    /// blank-line separation between runs.
    public internal(set) var leadingByTarget: [NodeRef: [[Comment]]] = [:]
    /// Same-line trailing comments per anchor, in source order.
    public internal(set) var trailingByTarget: [NodeRef: [Comment]] = [:]
    /// Comments not attached to any anchor — e.g. section dividers
    /// between top-level constructs, or comments stranded mid-expression.
    /// Stored in source order.
    public internal(set) var freestanding: [Comment] = []
    /// Detected `# METADATA` blocks. The block's individual comments
    /// also appear in `leadingByTarget` so the printer can emit them
    /// regardless of metadata-awareness.
    public internal(set) var metadataBlocks: [MetadataBlock] = []

    public init() {}

    /// Leading comment groups bound to `ref`, in source order.
    public func leadingGroups(of ref: NodeRef) -> [[Comment]] {
        leadingByTarget[ref] ?? []
    }

    /// All leading comments bound to `ref`, flattened across groups, in
    /// source order.
    public func leadingComments(of ref: NodeRef) -> [Comment] {
        (leadingByTarget[ref] ?? []).flatMap { $0 }
    }

    /// Same-line trailing comments bound to `ref`, in source order.
    public func trailingComments(of ref: NodeRef) -> [Comment] {
        trailingByTarget[ref] ?? []
    }

    /// The metadata block attached to `ref`, if any.
    public func metadata(of ref: NodeRef) -> MetadataBlock? {
        metadataBlocks.first { $0.target == ref }
    }

    /// Comments bound to `ref` at the given position. `nil` position
    /// returns an empty list — useful when the call site has an
    /// `Optional<CommentPosition>` and wants to default to "no
    /// expectation".
    public func commentsForPosition(_ position: CommentPosition?, of ref: NodeRef) -> [Comment] {
        switch position {
        case .leading: return leadingComments(of: ref)
        case .trailing: return trailingComments(of: ref)
        case .none: return []
        }
    }
}

/// Build a `CommentBindings` table for `arena` based on the comments
/// recorded during parsing.
///
/// This is a pure function over the arena's current state. Calling it
/// twice on the same arena produces the same bindings.
public func bindComments(_ arena: SyntaxArena) -> CommentBindings {
    var bindings = CommentBindings()
    let comments = arena.comments
    if comments.isEmpty { return bindings }

    let anchors = collectAnchors(arena: arena)
    if anchors.isEmpty {
        bindings.freestanding = comments
        return bindings
    }

    // Pass 1 — trailing detection.
    //
    // A comment at line L is trailing of anchor X if X ends on line L
    // and X's end offset is at-or-before the comment's start. Among
    // overlapping candidates we pick the one that ends latest (the
    // closest preceding anchor on the line).
    var trailingTarget: [Int: NodeRef] = [:]
    for (i, c) in comments.enumerated() {
        var bestAnchor: AnchorRef?
        for anchor in anchors {
            guard anchor.span.end.line == c.span.start.line,
                anchor.span.end.offset <= c.span.start.offset
            else { continue }
            if bestAnchor == nil || bestAnchor!.span.end < anchor.span.end {
                bestAnchor = anchor
            }
        }
        if let bestAnchor {
            trailingTarget[i] = bestAnchor.ref
        }
    }

    // Pass 2 — leading-run grouping and binding.
    //
    // Walk non-trailing comments, gathering them into contiguous runs
    // (consecutive line numbers). Each run binds to the next anchor:
    //   - METADATA runs always bind, regardless of blank-line gap.
    //   - Other runs bind only when the run ends on the line immediately
    //     above the anchor.
    var i = 0
    while i < comments.count {
        if trailingTarget[i] != nil {
            i += 1
            continue
        }
        let runStart = i
        var runEnd = i
        while runEnd + 1 < comments.count,
            trailingTarget[runEnd + 1] == nil,
            comments[runEnd + 1].span.start.line == comments[runEnd].span.start.line + 1
        {
            runEnd += 1
        }
        let runComments = Array(comments[runStart...runEnd])
        let runLastLine = comments[runEnd].span.start.line
        let runEndOffset = comments[runEnd].span.end.offset
        let isMetadata = runComments.first?.text == "# METADATA"

        // The next anchor that starts strictly after this run.
        let nextAnchor = anchors.first { $0.span.start.offset > runEndOffset }

        let bound: AnchorRef? = {
            guard let nextAnchor else { return nil }
            if isMetadata { return nextAnchor }
            return nextAnchor.span.start.line == runLastLine + 1 ? nextAnchor : nil
        }()

        if let bound {
            bindings.leadingByTarget[bound.ref, default: []].append(runComments)
            if isMetadata {
                // YAML body = run with the `# METADATA` header dropped,
                // each line stripped of the `#` (and one optional space).
                let body = runComments.dropFirst().map { stripCommentPrefix($0.text) }
                let blockSpan = SourceSpan(
                    start: runComments.first!.span.start,
                    end: runComments.last!.span.end
                )
                bindings.metadataBlocks.append(
                    MetadataBlock(
                        target: bound.ref,
                        lines: body,
                        defaultScope: defaultScope(for: bound.ref, in: arena),
                        span: blockSpan
                    ))
            }
        } else {
            bindings.freestanding.append(contentsOf: runComments)
        }
        i = runEnd + 1
    }

    // Apply trailing assignments in source order so that arrays stay sorted.
    for idx in trailingTarget.keys.sorted() {
        let target = trailingTarget[idx]!
        bindings.trailingByTarget[target, default: []].append(comments[idx])
    }

    return bindings
}

// MARK: - Internal helpers

/// A node that can host bound comments. Top-level constructs
/// (`packageDecl`, `importDecl`, `rule`) and literals inside brace-body
/// queries.
private struct AnchorRef {
    let ref: NodeRef
    let span: SourceSpan
}

/// Walk the arena and collect anchor nodes, sorted by start position.
///
/// Top-level: `packageDecl`, each `importDecl`, each `rule`.
/// Inside rules: every literal inside any `query` reachable through
/// rule body / `every` body / `not { … }` body / `else` body. Queries
/// inside comprehensions are intentionally NOT walked into (preserving
/// comments inside comprehensions is a follow-up).
private func collectAnchors(arena: SyntaxArena) -> [AnchorRef] {
    var anchors: [AnchorRef] = []
    guard let root = arena.root else { return anchors }
    walkForAnchors(root, in: arena, anchors: &anchors)
    anchors.sort { $0.span.start < $1.span.start }
    return anchors
}

private func walkForAnchors(
    _ ref: NodeRef, in arena: SyntaxArena, anchors: inout [AnchorRef]
) {
    let node = arena.node(at: ref)
    switch node {
    case .module(let pkg, let imports, let rules):
        anchors.append(AnchorRef(ref: pkg, span: arena.span(of: pkg)))
        for imp in imports {
            anchors.append(AnchorRef(ref: imp, span: arena.span(of: imp)))
        }
        for r in rules {
            anchors.append(AnchorRef(ref: r, span: arena.span(of: r)))
            walkForAnchors(r, in: arena, anchors: &anchors)
        }
    case .rule(_, _, let body, let elseClauses):
        if let body { walkForAnchors(body, in: arena, anchors: &anchors) }
        for ec in elseClauses { walkForAnchors(ec, in: arena, anchors: &anchors) }
    case .elseClause(_, let body):
        if let body { walkForAnchors(body, in: arena, anchors: &anchors) }
    case .query(let lits):
        for lit in lits {
            anchors.append(AnchorRef(ref: lit, span: arena.span(of: lit)))
            walkForAnchors(lit, in: arena, anchors: &anchors)
        }
    case .literal(let body, _):
        walkForAnchors(body, in: arena, anchors: &anchors)
    case .notLiteral(let target):
        // Target may be an expression OR a `query` (the `not { … }` form).
        walkForAnchors(target, in: arena, anchors: &anchors)
    case .every(_, _, _, let body):
        walkForAnchors(body, in: arena, anchors: &anchors)
    case .arrayCompr, .setCompr, .objectCompr:
        // Skip — comprehension bodies aren't anchored in this iteration.
        break
    default:
        // No nested queries reachable through other node kinds.
        break
    }
}

/// Strip the leading `#` (and one optional space) from a comment line.
/// `# title: foo` → `title: foo`; `#bare` → `bare`.
private func stripCommentPrefix(_ text: String) -> String {
    guard text.hasPrefix("#") else { return text }
    var t = text.dropFirst()
    if t.first == " " { t = t.dropFirst() }
    return String(t)
}

/// Default `MetadataScope` for an anchor based on its node kind.
/// Per OPA: metadata above a `package` decl → `package`; above a rule →
/// `rule`. Other anchors (imports) default to `rule`.
private func defaultScope(for ref: NodeRef, in arena: SyntaxArena) -> MetadataScope {
    switch arena.node(at: ref) {
    case .packageDecl: return .package
    case .rule: return .rule
    default: return .rule
    }
}
