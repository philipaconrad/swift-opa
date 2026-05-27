//
//  Parser.swift
//  Parser - public entry point.
//

import Foundation

public enum Parser {
    /// Parse a Rego source file into a populated `SyntaxArena`.
    ///
    /// On failure the returned errors describe what went wrong; the partially
    /// constructed arena is discarded. Phase 1 stops at the first error;
    /// recovery and multi-error reporting come later.
    public static func parse(source: SourceFile) -> Result<SyntaxArena, ParseErrors> {
        let arena = SyntaxArena(source: source)
        let grammar = Grammar(arena: arena)
        var input = Substring(source.contents)
        do {
            _ = try grammar.parseModule(&input)
            arena.bindings = bindComments(arena)
            return .success(arena)
        } catch let err as ParseError {
            return .failure(ParseErrors([err]))
        } catch {
            return .failure(
                ParseErrors([
                    ParseError(
                        kind: .other(String(describing: error)),
                        span: .empty,
                        message: String(describing: error)
                    )
                ])
            )
        }
    }
}
