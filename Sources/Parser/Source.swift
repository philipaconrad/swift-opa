//
//  Source.swift
//  Parser - source file representation, locations, spans, and string interning.
//

import Foundation

/// A Rego source file: its origin and full textual contents.
///
/// `SourceFile` is the unit of incremental parsing. Re-parsing a file means
/// rebuilding its `SyntaxArena`; `bundleID` lets callers attribute rules back
/// to the bundle they came from after parsing.
public struct SourceFile: Hashable, Sendable {
    public let url: URL
    public let bundleID: String?
    public let contents: String

    public init(url: URL, bundleID: String? = nil, contents: String) {
        self.url = url
        self.bundleID = bundleID
        self.contents = contents
    }
}

/// A position in a source file, expressed in 1-based lines/columns and a
/// 0-based UTF-8 byte offset into the file's contents.
public struct SourceLocation: Hashable, Sendable, Comparable {
    public let line: UInt32
    public let column: UInt32
    public let offset: UInt32

    public init(line: UInt32, column: UInt32, offset: UInt32) {
        self.line = line
        self.column = column
        self.offset = offset
    }

    public static let zero = SourceLocation(line: 1, column: 1, offset: 0)

    public static func < (lhs: SourceLocation, rhs: SourceLocation) -> Bool {
        lhs.offset < rhs.offset
    }
}

/// A half-open `[start, end)` byte range in a source file.
public struct SourceSpan: Hashable, Sendable {
    public let start: SourceLocation
    public let end: SourceLocation

    public init(start: SourceLocation, end: SourceLocation) {
        self.start = start
        self.end = end
    }

    public static let empty = SourceSpan(start: .zero, end: .zero)

    /// Returns the smallest span that covers both `lhs` and `rhs`.
    public static func union(_ lhs: SourceSpan, _ rhs: SourceSpan) -> SourceSpan {
        SourceSpan(
            start: min(lhs.start, rhs.start),
            end: max(lhs.end, rhs.end)
        )
    }

    /// True if `loc` lies within this span (start-inclusive, end-exclusive).
    public func contains(_ loc: SourceLocation) -> Bool {
        loc >= start && loc < end
    }
}

/// A small string interner. Identifiers and ref atoms in a `SyntaxArena` are
/// stored as opaque indices into a per-arena pool to keep `Node` values small.
public struct StringPool: Sendable {
    public struct Index: Hashable, Sendable {
        public let raw: UInt32

        public init(raw: UInt32) {
            self.raw = raw
        }
    }

    private var strings: [String] = []
    private var lookup: [String: Index] = [:]

    public init() {}

    public mutating func intern(_ s: String) -> Index {
        if let existing = lookup[s] {
            return existing
        }
        let idx = Index(raw: UInt32(strings.count))
        strings.append(s)
        lookup[s] = idx
        return idx
    }

    public subscript(_ idx: Index) -> String {
        strings[Int(idx.raw)]
    }

    public var count: Int { strings.count }
}
