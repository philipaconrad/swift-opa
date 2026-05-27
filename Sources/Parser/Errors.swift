//
//  Errors.swift
//  Parser - parse-error diagnostics with source spans.
//

import Foundation

/// A categorised parse error. The kind drives diagnostic phrasing; `span`
/// pinpoints the offending token or range so callers can render carets.
public struct ParseError: Error, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case expected(String)
        case unexpected(String)
        case reservedWord(String)
        case invalidNumber(String)
        case invalidString(String)
        case unterminatedString
        case unterminatedRawString
        case missingPackage
        case other(String)
    }

    public let kind: Kind
    public let span: SourceSpan
    public let message: String

    public init(kind: Kind, span: SourceSpan, message: String) {
        self.kind = kind
        self.span = span
        self.message = message
    }
}

extension ParseError: CustomStringConvertible {
    public var description: String {
        "\(span.start.line):\(span.start.column): \(message)"
    }
}

/// Aggregate parse errors. Today every failed parse produces exactly one
/// `ParseError`, but the API leaves room for multi-error reporting once the
/// parser learns to recover.
public struct ParseErrors: Error, Sendable, Hashable {
    public let errors: [ParseError]

    public init(_ errors: [ParseError]) {
        self.errors = errors
    }

    public var first: ParseError? { errors.first }
}

extension ParseErrors: CustomStringConvertible {
    public var description: String {
        errors.map(\.description).joined(separator: "\n")
    }
}
