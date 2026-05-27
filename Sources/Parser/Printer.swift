//
//  Printer.swift
//  Parser - emit Rego source from a parsed `SyntaxArena`.
//
//  Design notes:
//  - The printer walks the arena and produces a canonical, re-parseable
//    rendering. The contract is *round-trip stable*: `parse → print → parse
//    → print` is idempotent. The first emit may not match the original
//    input verbatim (formatting is normalised), but every subsequent emit
//    of the parsed result equals the previous one.
//  - Operator precedence drives parenthesisation: a child is wrapped only
//    when its precedence is strictly lower than the enclosing operator
//    (left side) or lower-or-equal (right side, for left-associativity).
//    Explicit `parens` nodes from the source are preserved.
//  - Comments are intentionally NOT emitted — they live in the arena's
//    free-floating sidecar and will be re-attached by the metadata-binding
//    pass (Phase 10). The printer drops them; round-trip stability still
//    holds because the parser doesn't re-emit them either.
//

import Foundation

/// Emit Rego source from a `SyntaxArena`.
public struct Printer {
    public let arena: SyntaxArena

    public init(arena: SyntaxArena) {
        self.arena = arena
    }

    /// Print the entire module rooted at `arena.root`. Returns "" if no
    /// root has been set.
    public func print() -> String {
        guard let root = arena.root else { return "" }
        return emit(root, indent: 0)
    }

    /// Print a specific node and its subtree. Useful for debugging or for
    /// printing arena fragments built outside `Parser.parse`.
    public func print(_ ref: NodeRef) -> String {
        return emit(ref, indent: 0)
    }

    // MARK: - Emit

    private func emit(_ ref: NodeRef, indent: Int) -> String {
        switch arena.node(at: ref) {
        case .module(let pkg, let imports, let rules):
            return emitModule(
                pkg: pkg, imports: imports, rules: rules, indent: indent)

        case .packageDecl(let path):
            return "package " + emit(path, indent: indent)

        case .ref(let head, let args):
            return emit(head, indent: indent) + args.map { emit($0, indent: indent) }.joined()

        case .refArgDot(let idx):
            return "." + arena.string(idx)

        case .refArgBracket(let inner):
            return "[" + emit(inner, indent: indent) + "]"

        case .variable(let idx):
            return arena.string(idx)

        case .scalarString(let idx):
            return "\"" + escapeString(arena.string(idx)) + "\""

        case .scalarRawString(let idx):
            return "`" + arena.string(idx) + "`"

        case .scalarNumber(let idx):
            return arena.string(idx)

        case .scalarBool(let b):
            return b ? "true" : "false"

        case .scalarNull:
            return "null"

        case .templateString(let parts, let isRaw):
            let delim: String = isRaw ? "`" : "\""
            var s = "$" + delim
            for part in parts {
                switch arena.node(at: part) {
                case .templateLiteral(let idx):
                    let text = arena.string(idx)
                    s += isRaw ? escapeRawTemplateLiteral(text) : escapeTemplateLiteral(text)
                case .templateExpr(let exprRef):
                    s += "{" + emit(exprRef, indent: indent) + "}"
                default:
                    s += emit(part, indent: indent)
                }
            }
            s += delim
            return s

        case .templateLiteral, .templateExpr:
            // These nodes are only emitted as part of a `templateString`
            // parent. Reaching them standalone is a defensive fallback.
            return ""

        case .array(let elements):
            return "[" + elements.map { emit($0, indent: indent) }.joined(separator: ", ") + "]"

        case .object(let pairs):
            return "{" + pairs.map { emit($0, indent: indent) }.joined(separator: ", ") + "}"

        case .set(let elements):
            if elements.isEmpty { return "set()" }
            return "{" + elements.map { emit($0, indent: indent) }.joined(separator: ", ") + "}"

        case .kvPair(let key, let value):
            return emit(key, indent: indent) + ": " + emit(value, indent: indent)

        case .binary(let op, let lhs, let rhs):
            let p = precedenceForBin(op)
            let lhsStr = wrapIfLower(lhs, p, indent: indent)
            let rhsStr = wrapIfLowerOrEqual(rhs, p, indent: indent)
            return lhsStr + " " + opString(op) + " " + rhsStr

        case .unary(let op, let operand):
            let opStr = unaryString(op)
            let operandStr = emit(operand, indent: indent)
            return precedence(operand) < 70 ? opStr + "(" + operandStr + ")" : opStr + operandStr

        case .logical(let op, let lhs, let rhs):
            let p = op == .and ? 25 : 20
            let lhsStr = wrapIfLower(lhs, p, indent: indent)
            let rhsStr = wrapIfLowerOrEqual(rhs, p, indent: indent)
            return lhsStr + " " + (op == .and ? "and" : "or") + " " + rhsStr

        case .call(let callee, let args):
            let argStrs = args.map { emit($0, indent: indent) }.joined(separator: ", ")
            return emit(callee, indent: indent) + "(" + argStrs + ")"

        case .parens(let inner):
            return "(" + emit(inner, indent: indent) + ")"

        case .query(let lits):
            // Bare query (no enclosing braces): each literal indented.
            // Used when callers explicitly want a query view; brace bodies
            // are rendered via `emitBraceBody`.
            let pad = String(repeating: "\t", count: indent)
            return lits.map { pad + emit($0, indent: indent) }.joined(separator: "\n")

        case .literal(let body, let mods):
            var s = emit(body, indent: indent)
            for m in mods {
                s += " " + emit(m, indent: indent)
            }
            return s

        case .withModifier(let target, let value):
            return "with " + emit(target, indent: indent) + " as " + emit(value, indent: indent)

        case .someDecl(let vars):
            return "some " + vars.map { emit($0, indent: indent) }.joined(separator: ", ")

        case .someIn(let key, let value, let domain):
            let head = key.map { emit($0, indent: indent) + ", " } ?? ""
            return "some " + head + emit(value, indent: indent) + " in "
                + emit(domain, indent: indent)

        case .notLiteral(let target):
            if case .query = arena.node(at: target) {
                return "not " + emitBraceBody(target, indent: indent)
            }
            return "not " + emit(target, indent: indent)

        case .every(let key, let value, let domain, let body):
            let kv = key.map { emit($0, indent: indent) + ", " } ?? ""
            return "every " + kv + emit(value, indent: indent) + " in "
                + emit(domain, indent: indent) + " " + emitBraceBody(body, indent: indent)

        case .arrayCompr(let term, let body):
            return "[" + emit(term, indent: indent) + " | "
                + emitInlineQuery(body, indent: indent) + "]"

        case .setCompr(let term, let body):
            return "{" + emit(term, indent: indent) + " | "
                + emitInlineQuery(body, indent: indent) + "}"

        case .objectCompr(let key, let value, let body):
            return "{" + emit(key, indent: indent) + ": " + emit(value, indent: indent) + " | "
                + emitInlineQuery(body, indent: indent) + "}"

        case .membership(let key, let value, let domain):
            let k = key.map { emit($0, indent: indent) + ", " } ?? ""
            return k + emit(value, indent: indent) + " in " + emit(domain, indent: indent)

        case .rule(let isDefault, let head, let body, let elseClauses):
            var s = isDefault ? "default " : ""
            s += emit(head, indent: indent)
            if let body, case .query(let lits) = arena.node(at: body) {
                if lits.count == 1, canInlineAsBody(lits[0]) {
                    // Single-literal body: inline form. Re-parses as a
                    // 1-literal query, structurally equivalent.
                    s += " " + emit(lits[0], indent: indent)
                } else if !lits.isEmpty {
                    // Multi-literal body OR a single-literal whose emit
                    // would start with `{` and isn't itself a
                    // comprehension. Inline would clash with brace-body
                    // parsing, so wrap in braces.
                    s += " " + emitBraceBody(body, indent: indent)
                }
            }
            for ec in elseClauses {
                s += " " + emit(ec, indent: indent)
            }
            return s

        case .ruleHead(let name, let kind, let value, let hasIf):
            var s = emit(name, indent: indent)
            switch kind {
            case .complete:
                break
            case .set(let member):
                s += " contains " + emit(member, indent: indent)
            case .function(let args):
                s += "(" + args.map { emit($0, indent: indent) }.joined(separator: ", ") + ")"
            }
            if let value {
                s += " := " + emit(value, indent: indent)
            }
            if hasIf {
                s += " if"
            }
            return s

        case .elseClause(let value, let body):
            var s = "else"
            if let value {
                s += " := " + emit(value, indent: indent)
            }
            if let body, case .query(let lits) = arena.node(at: body) {
                if lits.count == 1, canInlineAsBody(lits[0]) {
                    s += " if " + emit(lits[0], indent: indent)
                } else if !lits.isEmpty {
                    // Brace form (no `if`) — `else { … }`.
                    s += " " + emitBraceBody(body, indent: indent)
                }
            }
            return s

        case .importDecl(let path, let alias):
            var s = "import " + emit(path, indent: indent)
            if let alias {
                s += " as " + arena.string(alias)
            }
            return s
        }
    }

    /// Render a `query` node as a multi-line `{ … }` brace body, with each
    /// literal indented one level deeper than `indent`. Each literal is
    /// wrapped with its bound leading/trailing comments.
    private func emitBraceBody(_ queryRef: NodeRef, indent: Int) -> String {
        guard case .query(let lits) = arena.node(at: queryRef) else {
            // Defensive: a body should always be a query node, but emit a
            // single-line fallback if not.
            return "{ " + emit(queryRef, indent: indent) + " }"
        }
        if lits.isEmpty { return "{}" }
        let pad = String(repeating: "\t", count: indent + 1)
        let inner = lits.map { lit in
            indentLines(emitWithBindings(lit, indent: indent + 1), by: pad)
        }.joined(separator: "\n")
        let close = String(repeating: "\t", count: indent)
        return "{\n" + inner + "\n" + close + "}"
    }

    /// Render a `query` node inline (semicolon-separated). Used in
    /// comprehension bodies where multi-line formatting hurts readability.
    private func emitInlineQuery(_ queryRef: NodeRef, indent: Int) -> String {
        guard case .query(let lits) = arena.node(at: queryRef) else {
            return emit(queryRef, indent: indent)
        }
        return lits.map { emit($0, indent: indent) }.joined(separator: "; ")
    }

    // MARK: - Comment-aware emission

    /// Emit a node wrapped with its bound leading and trailing comments.
    ///
    /// The output is unindented at the first column; callers that need
    /// indentation should pass the result through `indentLines` afterward.
    /// Multiple leading-comment groups are separated by blank lines;
    /// trailing comments are appended on the node's last line, separated
    /// by a single space.
    private func emitWithBindings(_ ref: NodeRef, indent: Int) -> String {
        let leadingGroups = arena.bindings.leadingGroups(of: ref)
        let trailingComments = arena.bindings.trailingComments(of: ref)

        var output = ""
        for (g, group) in leadingGroups.enumerated() {
            if g > 0 { output += "\n\n" }
            for (j, c) in group.enumerated() {
                if j > 0 { output += "\n" }
                output += c.text
            }
        }
        if !output.isEmpty { output += "\n" }

        output += emit(ref, indent: indent)

        for tc in trailingComments {
            output += " " + tc.text
        }
        return output
    }

    /// Apply `pad` to every non-empty line of `s`. Empty lines remain
    /// empty (so blank-line separators between leading-comment groups
    /// don't pick up stray indent).
    private func indentLines(_ s: String, by pad: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.isEmpty ? "" : pad + String(line)
        }.joined(separator: "\n")
    }

    /// Group consecutive comments that sit on adjacent source lines into
    /// runs. Used to break freestanding comments back into the visual
    /// blocks the source had — a blank line between two comments yields
    /// two groups instead of one.
    private func groupConsecutive(_ comments: [Comment]) -> [[Comment]] {
        var groups: [[Comment]] = []
        var current: [Comment] = []
        for c in comments {
            if let last = current.last, c.span.start.line == last.span.start.line + 1 {
                current.append(c)
            } else {
                if !current.isEmpty { groups.append(current) }
                current = [c]
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    /// True if `ref` is an `importDecl`. Used to decide whether the gap
    /// between two top-level constructs should be a single newline (tight
    /// imports) or a blank line.
    private func isImportDecl(_ ref: NodeRef) -> Bool {
        if case .importDecl = arena.node(at: ref) { return true }
        return false
    }

    /// Render the module: package, imports, rules — with leading/
    /// trailing comments on each construct, and freestanding comments
    /// injected into the gaps in source order.
    private func emitModule(
        pkg: NodeRef, imports: [NodeRef], rules: [NodeRef], indent: Int
    ) -> String {
        let allTopLevel: [NodeRef] = [pkg] + imports + rules
        var output = ""
        var prevEndLine: UInt32 = 0

        for (i, item) in allTopLevel.enumerated() {
            let span = arena.span(of: item)

            // Freestanding comments in the gap between the previous item
            // and this one (or before the first item).
            let gapComments = arena.bindings.freestanding.filter { c in
                c.span.start.line > prevEndLine && c.span.start.line < span.start.line
            }
            let gapGroups = groupConsecutive(gapComments)

            if i > 0 {
                let prev = allTopLevel[i - 1]
                let bothImports = isImportDecl(prev) && isImportDecl(item)
                if gapGroups.isEmpty {
                    // Tight imports get a single newline; everything else
                    // gets a blank line between sections.
                    output += bothImports ? "\n" : "\n\n"
                } else {
                    output += "\n\n"
                }
            }

            for (g, group) in gapGroups.enumerated() {
                if g > 0 { output += "\n\n" }
                output += group.map { $0.text }.joined(separator: "\n")
            }
            if !gapGroups.isEmpty { output += "\n\n" }

            output += emitWithBindings(item, indent: indent)
            prevEndLine = span.end.line
        }

        // Freestanding comments after the last top-level construct.
        let trailingFree = arena.bindings.freestanding.filter { $0.span.start.line > prevEndLine }
        let trailingGroups = groupConsecutive(trailingFree)
        for group in trailingGroups {
            output += "\n\n" + group.map { $0.text }.joined(separator: "\n")
        }

        return output
    }

    /// Can this literal be inlined as a single-literal rule body without
    /// causing a parse ambiguity?
    ///
    /// Comprehensions are inline-safe: the parser's
    /// `tryParseComprehensionAsBody` handles them. Anything else whose
    /// emit would start with `{` must be brace-wrapped, because the
    /// parser would otherwise see the `{` and try to parse a brace-block
    /// body — which fails as soon as the body's contents aren't a query.
    private func canInlineAsBody(_ ref: NodeRef) -> Bool {
        switch arena.node(at: ref) {
        case .arrayCompr, .setCompr, .objectCompr:
            return true
        default:
            return !wouldEmitStartWithBrace(ref)
        }
    }

    /// Would this node's emitted form start with `{`?
    ///
    /// Walks down the leftmost child of the AST so a binary, logical, or
    /// `with`-modified literal is detected when its head term is itself
    /// `{`-starting (e.g. `{1: 1} == {1: 1.0}`).
    private func wouldEmitStartWithBrace(_ ref: NodeRef) -> Bool {
        switch arena.node(at: ref) {
        case .object, .setCompr, .objectCompr:
            return true
        case .set(let elements):
            // Empty set is `set(`; non-empty is `{`.
            return !elements.isEmpty
        case .binary(_, let lhs, _),
            .logical(_, let lhs, _):
            return wouldEmitStartWithBrace(lhs)
        case .literal(let body, _):
            return wouldEmitStartWithBrace(body)
        case .membership(let key, let value, _):
            return wouldEmitStartWithBrace(key ?? value)
        case .ref(let head, _):
            return wouldEmitStartWithBrace(head)
        case .call(let callee, _):
            return wouldEmitStartWithBrace(callee)
        default:
            return false
        }
    }

    // MARK: - Precedence

    private func wrapIfLower(_ ref: NodeRef, _ p: Int, indent: Int) -> String {
        let s = emit(ref, indent: indent)
        return precedence(ref) < p ? "(" + s + ")" : s
    }

    private func wrapIfLowerOrEqual(_ ref: NodeRef, _ p: Int, indent: Int) -> String {
        let s = emit(ref, indent: indent)
        return precedence(ref) <= p ? "(" + s + ")" : s
    }

    /// Effective precedence of `ref`. Higher binds tighter. Primary
    /// expressions (variables, scalars, calls, parens, comprehensions, …)
    /// are 100. Operators map to their parser-side precedence.
    private func precedence(_ ref: NodeRef) -> Int {
        switch arena.node(at: ref) {
        case .binary(let op, _, _): return precedenceForBin(op)
        case .logical(let op, _, _): return op == .and ? 25 : 20
        case .unary: return 70
        case .membership: return 30
        default: return 100
        }
    }

    private func precedenceForBin(_ op: BinOp) -> Int {
        switch op {
        case .assign, .unify: return 10
        case .eq, .ne, .lt, .le, .gt, .ge, .in: return 30
        case .bitOr: return 35
        case .bitAnd: return 40
        case .add, .sub: return 50
        case .mul, .div, .mod: return 60
        }
    }

    // MARK: - Operator strings

    private func opString(_ op: BinOp) -> String {
        switch op {
        case .eq: return "=="
        case .ne: return "!="
        case .lt: return "<"
        case .le: return "<="
        case .gt: return ">"
        case .ge: return ">="
        case .add: return "+"
        case .sub: return "-"
        case .mul: return "*"
        case .div: return "/"
        case .mod: return "%"
        case .bitAnd: return "&"
        case .bitOr: return "|"
        case .in: return "in"
        case .assign: return ":="
        case .unify: return "="
        }
    }

    private func unaryString(_ op: UnaryOp) -> String {
        switch op {
        case .minus: return "-"
        }
    }

    // MARK: - Escaping

    /// Escape a string for emission inside a `"…"` literal.
    ///
    /// We iterate over `Unicode.Scalar`s rather than `Character`s because
    /// CRLF is a single grapheme cluster — switching over a `Character`
    /// "\r" wouldn't match a "\r\n" cluster, and we'd lose the trailing
    /// `\n`. Per-scalar iteration keeps each control character separately
    /// addressable.
    private func escapeString(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            appendEscaped(scalar, into: &out, includeCurly: false)
        }
        return out
    }

    /// Escape the literal portion of a non-raw template string. Same as
    /// `escapeString` plus `{` → `\{` so re-parsing doesn't mistake the
    /// brace for a template-expression delimiter.
    private func escapeTemplateLiteral(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            appendEscaped(scalar, into: &out, includeCurly: true)
        }
        return out
    }

    /// Escape the literal portion of a raw template string. Raw strings
    /// don't process backslash escapes during parsing, so the only thing
    /// we need to escape is `{` (which would otherwise open a
    /// template-expression). All other characters round-trip verbatim.
    private func escapeRawTemplateLiteral(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            if scalar == "{" {
                out += "\\{"
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private func appendEscaped(
        _ scalar: Unicode.Scalar, into out: inout String, includeCurly: Bool
    ) {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case "\u{08}": out += "\\b"
        case "\u{0C}": out += "\\f"
        case "{" where includeCurly: out += "\\{"
        default:
            if scalar.value < 0x20 {
                out += String(format: "\\u%04x", scalar.value)
            } else {
                out += String(scalar)
            }
        }
    }
}
