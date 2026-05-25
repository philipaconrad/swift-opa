//
//  Syntax.swift
//  Parser - syntactic node types and the per-file `SyntaxArena` that owns them.
//
//  Design notes:
//  - One arena per source file. The flat `nodes` buffer + parallel `spans`
//    buffer give us locality at the file level (see "Flattening ASTs", Sampson
//    2023). Cross-file refs are `(ArenaID, NodeRef)` pairs handled at the
//    `ModuleSet` level.
//  - `Node` is a Swift enum with associated values. Variable-length child
//    lists live inline as `[NodeRef]` for now; the side-table compaction pass
//    is intentionally deferred until we have a reason to introduce it.
//  - Comments are recorded as a free-floating sidecar (`comments`) sorted by
//    source span. Range queries (`comments(in:)`, `leadingComments(of:)`)
//    drive feature work that needs file-, package-, or rule-scoped comments.
//

import Foundation

/// Index of a `Node` inside a single `SyntaxArena`. Plain 32-bit handle.
/// Cross-arena references are not modelled here; that's the `ModuleSet` job.
public struct NodeRef: Hashable, Sendable {
    public let raw: UInt32

    public init(raw: UInt32) {
        self.raw = raw
    }
}

/// Infix binary operators that participate in precedence-climbing parsing.
/// Logical `and`/`or` are *not* here — those are handled by `LogicalOp` so
/// the AST keeps the higher-level structure of the grammar's `expr-logical`.
public enum BinOp: Sendable, Hashable {
    /// `==`
    case eq
    /// `!=`
    case ne
    /// `<`
    case lt
    /// `<=`
    case le
    /// `>`
    case gt
    /// `>=`
    case ge
    /// `+`
    case add
    /// `-`
    case sub
    /// `*`
    case mul
    /// `/`
    case div
    /// `%`
    case mod
    /// `&` — set intersection / "binary and" in the grammar.
    case bitAnd
    /// `|` — set union / "binary or" in the grammar.
    case bitOr
    /// `in` membership test (boolean form, no key).
    case `in`
    /// `:=` local assignment.
    case assign
    /// `=` unification.
    case unify
}

public enum UnaryOp: Sendable, Hashable {
    /// Leading `-` on a number or ref.
    case minus
}

public enum LogicalOp: Sendable, Hashable {
    case and
    case or
}

/// Shape of a rule head.
///
/// `complete` covers everything that isn't a function definition or a
/// `contains` set rule. The bracket-key form (`name[k] := v`) collapses
/// into `complete` because the `[k]` lives inside the head's `name` ref
/// (it's a `refArgBracket`); name resolution decides whether `k` is a free
/// variable or a literal lookup.
public enum RuleHeadKind: Sendable, Hashable {
    /// Default head: optional `:= value` plus optional `if`.
    case complete
    /// `name contains member` — set rule.
    case set(member: NodeRef)
    /// `name(args...) [:= value]` — function definition.
    case function(args: [NodeRef])
}

/// Syntactic shape of a parsed Rego construct. New cases are added per phase
/// rather than reserved upfront, so the enum reflects what the parser
/// actually produces today.
public enum Node: Sendable, Hashable {
    /// File root. The single `package` declaration is required by the grammar.
    case module(package: NodeRef, imports: [NodeRef], rules: [NodeRef])

    /// `package <ref>` — `path` points at the `ref` node holding the dotted
    /// package path.
    case packageDecl(path: NodeRef)

    /// `<head>{ <ref-arg> }` — see `Node.refArgDot` / `Node.refArgBracket`.
    case ref(head: NodeRef, args: [NodeRef])

    /// `.name` reference argument.
    case refArgDot(StringPool.Index)

    /// `[expr]` reference argument — the inner node is a full expression.
    case refArgBracket(NodeRef)

    /// Bare variable term (also used as a ref head).
    case variable(StringPool.Index)

    /// Double-quoted string with escapes already decoded into the interned
    /// payload.
    case scalarString(StringPool.Index)

    /// Backtick-delimited raw string. Payload is the verbatim text between
    /// the delimiters (no escape processing).
    case scalarRawString(StringPool.Index)

    /// JSON-format number. We keep the raw text rather than a `Decimal` so
    /// the source representation can be round-tripped without precision loss
    /// or normalisation. Numeric value is computed on demand by callers.
    case scalarNumber(StringPool.Index)

    /// `true` or `false`.
    case scalarBool(Bool)

    /// `null`.
    case scalarNull

    /// `$"..."` or `` $`...` ``. `parts` is an alternating sequence of
    /// `templateLiteral` and `templateExpr` nodes in source order. `isRaw`
    /// distinguishes the two body styles for round-tripping.
    case templateString(parts: [NodeRef], isRaw: Bool)

    /// A literal text segment of a template string, with escapes already
    /// applied (for the non-raw flavour) or verbatim (for the raw flavour).
    case templateLiteral(StringPool.Index)

    /// A `{ expr }` block inside a template string. The `NodeRef` is the
    /// parsed expression.
    case templateExpr(NodeRef)

    /// `[ term, term, ... ]`. Trailing commas tolerated.
    case array(elements: [NodeRef])

    /// `{ k: v, k: v, ... }`. `pairs` is a list of `kvPair` nodes; an empty
    /// list represents the empty object literal `{}`.
    case object(pairs: [NodeRef])

    /// `{ e1, e2, ... }` (non-empty) or `set()` (empty). The empty-set
    /// syntax is represented here with `elements == []`; `{}` is always an
    /// empty object, never an empty set.
    case set(elements: [NodeRef])

    /// `key: value` entry inside an object literal.
    case kvPair(key: NodeRef, value: NodeRef)

    /// `lhs <op> rhs` for any infix `BinOp`. Logical `and`/`or` use
    /// `Node.logical` instead.
    case binary(op: BinOp, lhs: NodeRef, rhs: NodeRef)

    /// Unary expression — currently only `-`.
    case unary(op: UnaryOp, operand: NodeRef)

    /// `lhs and rhs` / `lhs or rhs`.
    case logical(op: LogicalOp, lhs: NodeRef, rhs: NodeRef)

    /// `callee(args...)` function call.
    case call(callee: NodeRef, args: [NodeRef])

    /// `(expr)` parenthesised expression. Preserved in the AST so source
    /// round-tripping doesn't lose user-written grouping.
    case parens(NodeRef)

    /// A query — a sequence of literals separated by `;` or newlines. Used
    /// for rule bodies, `not { … }` blocks, `every` bodies, and
    /// comprehension filters.
    case query(literals: [NodeRef])

    /// A single statement inside a query: a body (expr / someDecl / notLiteral)
    /// optionally modified by one or more `with` modifiers. The wrapper is
    /// only added when at least one modifier is present; bare bodies appear
    /// in queries as the underlying body NodeRef.
    case literal(body: NodeRef, withModifiers: [NodeRef])

    /// `with <target> as <value>`.
    case withModifier(target: NodeRef, value: NodeRef)

    /// `some var, var, …` — declares one or more locals without an `in`.
    case someDecl(vars: [NodeRef])

    /// `some [key,] value in domain` — declare-and-iterate.
    case someIn(key: NodeRef?, value: NodeRef, domain: NodeRef)

    /// `not <target>` — target is either an expression or a `.query`
    /// (the `not { … }` block form).
    case notLiteral(target: NodeRef)

    /// `every [key,] value in domain { body }` — universal quantifier.
    case every(key: NodeRef?, value: NodeRef, domain: NodeRef, body: NodeRef)

    /// `[ term | query ]` array comprehension.
    case arrayCompr(term: NodeRef, body: NodeRef)

    /// `{ term | query }` set comprehension.
    case setCompr(term: NodeRef, body: NodeRef)

    /// `{ key: value | query }` object comprehension.
    case objectCompr(key: NodeRef, value: NodeRef, body: NodeRef)

    /// `key, value in domain` membership term — used in expression position
    /// (typically inside `(...)`) where the parser needs to distinguish the
    /// 2-element membership form from `expr in expr`. Semantically a builtin
    /// call to `internal.member_2` / `internal.member_3` in upstream OPA.
    case membership(key: NodeRef?, value: NodeRef, domain: NodeRef)

    /// A top-level rule. `head` is a `ruleHead`, `body` is an optional
    /// `query`, and `elseClauses` is a (possibly empty) sequence of
    /// `elseClause` nodes. `default` corresponds to the `default` keyword.
    case rule(default: Bool, head: NodeRef, body: NodeRef?, elseClauses: [NodeRef])

    /// Rule head — `name [:= value] [if]` and the variants distinguished by
    /// `RuleHeadKind`. `hasIf` records whether the source contained the `if`
    /// keyword so we can round-trip `name := true` vs `name := true if {…}`.
    case ruleHead(name: NodeRef, kind: RuleHeadKind, value: NodeRef?, hasIf: Bool)

    /// `else [:= value] [if literal | { query }]`. Both fields are
    /// independently optional per the grammar; in practice at least one is
    /// usually present.
    case elseClause(value: NodeRef?, body: NodeRef?)

    /// `import ref [as var]`. `path` is a `ref` node; `alias` is the
    /// interned alias identifier or `nil` if absent.
    case importDecl(path: NodeRef, alias: StringPool.Index?)
}

/// A `# ...` source comment. Comments are not bound to any node at parse
/// time; consumers do span-based lookups via `SyntaxArena.comments(in:)`.
public struct Comment: Sendable, Hashable {
    public let span: SourceSpan
    public let text: String

    public init(span: SourceSpan, text: String) {
        self.span = span
        self.text = text
    }
}

/// Owns a parsed file: its source, the flat node buffer, parallel spans,
/// interned identifiers, and free-floating comments.
///
/// The arena is mutable during parsing and is intended to be treated as
/// frozen afterwards. We don't enforce that at the type level yet; if/when
/// callers need to share arenas across actors we'll either split a
/// builder/snapshot pair or wrap the storage in CoW.
public final class SyntaxArena {
    public let source: SourceFile

    /// Flat buffer of all parsed nodes in construction order.
    public private(set) var nodes: [Node] = []

    /// Source span for `nodes[i]`. Same length as `nodes`.
    public private(set) var spans: [SourceSpan] = []

    /// Interned identifier storage referenced by `Node.refArgDot`,
    /// `Node.variable`, etc.
    public private(set) var strings: StringPool = StringPool()

    /// All comments in the file, sorted by `span.start`.
    public private(set) var comments: [Comment] = []

    /// Root node (the `Node.module` produced by `parse`). Optional during
    /// construction, set by the parser before returning.
    public private(set) var root: NodeRef?

    public init(source: SourceFile) {
        self.source = source
    }

    /// Append a node and its span. Returns the new `NodeRef`.
    @discardableResult
    public func add(_ node: Node, span: SourceSpan) -> NodeRef {
        let ref = NodeRef(raw: UInt32(nodes.count))
        nodes.append(node)
        spans.append(span)
        return ref
    }

    public func setRoot(_ ref: NodeRef) {
        root = ref
    }

    /// Append a comment. The parser appends in source order, so the resulting
    /// `comments` array stays sorted by `span.start`.
    public func appendComment(_ comment: Comment) {
        comments.append(comment)
    }

    public func intern(_ string: String) -> StringPool.Index {
        strings.intern(string)
    }

    public func node(at ref: NodeRef) -> Node {
        nodes[Int(ref.raw)]
    }

    public func span(of ref: NodeRef) -> SourceSpan {
        spans[Int(ref.raw)]
    }

    public func string(_ idx: StringPool.Index) -> String {
        strings[idx]
    }

    /// Replace the node stored at `ref`. The span and any sidecar state are
    /// preserved. Used by AST manipulation passes (statement reordering,
    /// constant folding, …).
    public func replace(_ ref: NodeRef, with node: Node) {
        nodes[Int(ref.raw)] = node
    }

    /// Replace the span associated with `ref`. Useful when a rewriter wants
    /// to widen or shift the source mapping after an edit.
    public func replaceSpan(_ ref: NodeRef, with span: SourceSpan) {
        spans[Int(ref.raw)] = span
    }

    /// Comments whose span lies entirely within `span`.
    public func comments(in span: SourceSpan) -> ArraySlice<Comment> {
        let lo = comments.firstIndex { $0.span.start >= span.start } ?? comments.endIndex
        let hi = comments[lo...].firstIndex { $0.span.end > span.end } ?? comments.endIndex
        return comments[lo..<hi]
    }

    /// Comments inside the source span of `node`.
    public func comments(in node: NodeRef) -> ArraySlice<Comment> {
        comments(in: span(of: node))
    }

    /// Comments immediately preceding `node` on contiguous prior lines.
    ///
    /// "Immediately preceding" means the last comment ends on the line just
    /// above the node's start line, and any earlier comments included in the
    /// returned slice form an unbroken run of one-comment-per-line above
    /// that. A blank line between comments breaks the run.
    public func leadingComments(of node: NodeRef) -> ArraySlice<Comment> {
        let target = span(of: node).start

        // Restrict to comments that start before the node.
        var endIdx = comments.endIndex
        while endIdx > comments.startIndex, comments[endIdx - 1].span.start >= target {
            endIdx -= 1
        }

        // Walk backward, accepting each comment whose start line is exactly
        // one less than the previous accepted line (or the node's line for
        // the first iteration).
        var startIdx = endIdx
        var expectedLine = target.line
        while startIdx > comments.startIndex {
            let candidate = comments[startIdx - 1]
            guard candidate.span.start.line + 1 == expectedLine else { break }
            expectedLine = candidate.span.start.line
            startIdx -= 1
        }

        return comments[startIdx..<endIdx]
    }

    /// All `NodeRef`-typed children of `ref`, in their declaration order in
    /// the underlying `Node` case. Comments and side-table state are not
    /// returned. Used as the building block for visitor traversals.
    public func children(of ref: NodeRef) -> [NodeRef] {
        switch nodes[Int(ref.raw)] {
        case .module(let pkg, let imports, let rules):
            return [pkg] + imports + rules
        case .packageDecl(let path):
            return [path]
        case .ref(let head, let args):
            return [head] + args
        case .refArgDot:
            return []
        case .refArgBracket(let inner):
            return [inner]
        case .variable, .scalarString, .scalarRawString, .scalarNumber,
            .scalarBool, .scalarNull, .templateLiteral:
            return []
        case .templateString(let parts, _):
            return parts
        case .templateExpr(let inner):
            return [inner]
        case .array(let elements):
            return elements
        case .object(let pairs):
            return pairs
        case .set(let elements):
            return elements
        case .kvPair(let key, let value):
            return [key, value]
        case .binary(_, let lhs, let rhs):
            return [lhs, rhs]
        case .unary(_, let operand):
            return [operand]
        case .logical(_, let lhs, let rhs):
            return [lhs, rhs]
        case .call(let callee, let args):
            return [callee] + args
        case .parens(let inner):
            return [inner]
        case .query(let lits):
            return lits
        case .literal(let body, let mods):
            return [body] + mods
        case .withModifier(let target, let value):
            return [target, value]
        case .someDecl(let vars):
            return vars
        case .someIn(let key, let value, let domain):
            return ([key].compactMap { $0 }) + [value, domain]
        case .notLiteral(let target):
            return [target]
        case .every(let key, let value, let domain, let body):
            return ([key].compactMap { $0 }) + [value, domain, body]
        case .arrayCompr(let term, let body),
            .setCompr(let term, let body):
            return [term, body]
        case .objectCompr(let key, let value, let body):
            return [key, value, body]
        case .membership(let key, let value, let domain):
            var result: [NodeRef] = []
            if let key { result.append(key) }
            result.append(value)
            result.append(domain)
            return result
        case .rule(_, let head, let body, let elses):
            var result = [head]
            if let body { result.append(body) }
            result.append(contentsOf: elses)
            return result
        case .ruleHead(let name, let kind, let value, _):
            var result = [name]
            switch kind {
            case .complete:
                break
            case .set(let member):
                result.append(member)
            case .function(let args):
                result.append(contentsOf: args)
            }
            if let value { result.append(value) }
            return result
        case .elseClause(let value, let body):
            var result: [NodeRef] = []
            if let value { result.append(value) }
            if let body { result.append(body) }
            return result
        case .importDecl(let path, _):
            return [path]
        }
    }

    /// Pre-order walk from `root`. The closure receives every node ref in
    /// the subtree exactly once.
    public func walk(from root: NodeRef, _ visit: (NodeRef) -> Void) {
        visit(root)
        for child in children(of: root) {
            walk(from: child, visit)
        }
    }
}

/// Identifier of a `SyntaxArena` inside a `ModuleSet`. Opaque to consumers.
public struct ArenaID: Hashable, Sendable {
    public let raw: UInt32

    public init(raw: UInt32) {
        self.raw = raw
    }
}
