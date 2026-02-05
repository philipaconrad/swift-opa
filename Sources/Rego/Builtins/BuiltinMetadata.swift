import AST
import Foundation

/// Note(philipc): The file is mostly a machine translation with minor touch-ups
/// from the Rego `Builtin` struct defined upstream in:
///   https://github.com/open-policy-agent/opa/blob/main/v1/ast/builtins.go
/// It allows us port over metadata and type signatures for builtin
/// functions in a way that maps strongly to the original design in Golang.

/// Represents a built-in function supported by OPA. Every built-in function is uniquely identified by a name.
public struct BuiltinMetadata: Codable {
    /// Unique name of built-in function, e.g., <name>(arg1,arg2,...,argN)
    public let name: String

    /// Description of what the built-in function does
    public let description: String?

    /// Categories of the built-in function. Omitted for namespaced built-ins,
    /// i.e. "array.concat" is taken to be of the "array" category.
    /// "minus" for example, is part of two categories: numbers and sets.
    public let categories: [String]?

    /// Built-in function type declaration
    public let decl: TypeSystem.Function

    /// Unique name of infix operator. Default should be unset.
    public let infix: String?

    /// Indicates if the built-in acts as a relation
    public let relation: Bool?

    /// Indicates if the built-in returns non-deterministic results
    public let nondeterministic: Bool?

    /// Indicates if the built-in has been deprecated (not serialized)
    public let deprecated: Bool

    /// Built-in needs no data from the built-in context (not serialized)
    public let canSkipBctx: Bool

    // MARK: - Initializers

    /// Full initializer with all parameters
    public init(
        name: String,
        description: String? = nil,
        categories: [String]? = nil,
        decl: TypeSystem.Function,
        infix: String? = nil,
        relation: Bool? = nil,
        nondeterministic: Bool? = nil,
        deprecated: Bool = false,
        canSkipBctx: Bool = true
    ) {
        self.name = name
        self.description = description
        self.categories = categories
        self.decl = decl
        self.infix = infix
        self.relation = relation
        self.nondeterministic = nondeterministic
        self.deprecated = deprecated
        self.canSkipBctx = canSkipBctx
    }

    /// Convenience initializer for simple functions
    public init(
        name: String,
        description: String? = nil,
        args: [TypeSystem.RegoType],
        result: TypeSystem.RegoType? = nil,
        categories: [String]? = nil,
        canSkipBctx: Bool = true
    ) {
        self.init(
            name: name,
            description: description,
            categories: categories,
            decl: TypeSystem.Function(args: args, result: result),
            canSkipBctx: canSkipBctx
        )
    }

    /// Convenience initializer for variadic functions
    public init(
        name: String,
        description: String? = nil,
        args: [TypeSystem.RegoType],
        variadic: TypeSystem.RegoType,
        result: TypeSystem.RegoType? = nil,
        categories: [String]? = nil,
        canSkipBctx: Bool = false  // Variadic functions typically need context
    ) {
        self.init(
            name: name,
            description: description,
            categories: categories,
            decl: TypeSystem.Function(args: args, result: result, variadic: variadic),
            canSkipBctx: canSkipBctx
        )
    }

    /// Convenience initializer for infix operators
    public init(
        name: String,
        infix: String,
        description: String? = nil,
        args: [TypeSystem.RegoType],
        result: TypeSystem.RegoType? = nil,
        categories: [String]? = nil,
        canSkipBctx: Bool = true
    ) {
        self.init(
            name: name,
            description: description,
            categories: categories,
            decl: TypeSystem.Function(args: args, result: result),
            infix: infix,
            canSkipBctx: canSkipBctx
        )
    }

    // MARK: - Codable Implementation

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case categories
        case decl
        case infix
        case relation
        case nondeterministic
        // deprecated and canSkipBctx are not serialized (equivalent to json:"-")
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.categories = try container.decodeIfPresent([String].self, forKey: .categories)

        // Decode the function declaration
        let declWrapper = try container.decode(AnyRegoType.self, forKey: .decl)
        guard let function = declWrapper.type as? TypeSystem.Function else {
            throw DecodingError.typeMismatch(
                TypeSystem.Function.self,
                DecodingError.Context(
                    codingPath: container.codingPath + [CodingKeys.decl],
                    debugDescription: "Expected Function type for decl field"
                )
            )
        }
        self.decl = function

        self.infix = try container.decodeIfPresent(String.self, forKey: .infix)
        self.relation = try container.decodeIfPresent(Bool.self, forKey: .relation)
        self.nondeterministic = try container.decodeIfPresent(Bool.self, forKey: .nondeterministic)

        // Non-serialized fields get default values
        self.deprecated = false
        self.canSkipBctx = true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)

        // Only encode optional fields if they have values (omitempty behavior)
        if let description = description, !description.isEmpty {
            try container.encode(description, forKey: .description)
        }

        if let categories = categories, !categories.isEmpty {
            try container.encode(categories, forKey: .categories)
        }

        try container.encode(AnyRegoType(decl), forKey: .decl)

        if let infix = infix, !infix.isEmpty {
            try container.encode(infix, forKey: .infix)
        }

        if let relation = relation, relation {
            try container.encode(relation, forKey: .relation)
        }

        if let nondeterministic = nondeterministic, nondeterministic {
            try container.encode(nondeterministic, forKey: .nondeterministic)
        }
    }

    // MARK: - Helper Methods

    /// Returns true if the Builtin function is deprecated and will be removed in a future release
    public var isDeprecated: Bool {
        return deprecated
    }

    /// Returns true if the Builtin function returns non-deterministic results
    public var isNondeterministic: Bool {
        return nondeterministic ?? false
    }

    /// Returns true if the built-in needs the built-in context
    public var needsBuiltInContext: Bool {
        return !canSkipBctx
    }

    /// Returns the arity (number of arguments) of the function
    public var arity: Int {
        return decl.args.count
    }

    /// Returns true if a variable in the i-th position will be bound by evaluating the call expression
    public func isTargetPos(_ i: Int) -> Bool {
        return arity == i
    }

    /// Returns a reference that refers to the built-in function (name split by dots)
    public var ref: [String] {
        return name.split(separator: ".").map(String.init)
    }

    /// Returns a minimal copy with descriptions and categories stripped out
    public func minimal() -> BuiltinMetadata {
        let minimalDecl: TypeSystem.Function
        if let variadic = decl.variadic {
            minimalDecl = TypeSystem.Function(args: decl.args, result: decl.result, variadic: variadic)
        } else {
            minimalDecl = TypeSystem.Function(args: decl.args, result: decl.result)
        }

        return BuiltinMetadata(
            name: name,
            description: nil,
            categories: nil,
            decl: minimalDecl,
            infix: infix,
            relation: relation,
            nondeterministic: nondeterministic,
            deprecated: deprecated,
            canSkipBctx: canSkipBctx
        )
    }
}

// MARK: - Builder-style Methods

extension BuiltinMetadata {

    /// Creates a copy with the deprecated flag set
    public func deprecated(_ isDeprecated: Bool = true) -> BuiltinMetadata {
        return BuiltinMetadata(
            name: name,
            description: description,
            categories: categories,
            decl: decl,
            infix: infix,
            relation: relation,
            nondeterministic: nondeterministic,
            deprecated: isDeprecated,
            canSkipBctx: canSkipBctx
        )
    }

    /// Creates a copy with the nondeterministic flag set
    public func nondeterministic(_ isNondeterministic: Bool = true) -> BuiltinMetadata {
        return BuiltinMetadata(
            name: name,
            description: description,
            categories: categories,
            decl: decl,
            infix: infix,
            relation: relation,
            nondeterministic: isNondeterministic,
            deprecated: deprecated,
            canSkipBctx: canSkipBctx
        )
    }

    /// Creates a copy with the relation flag set
    public func relation(_ isRelation: Bool = true) -> BuiltinMetadata {
        return BuiltinMetadata(
            name: name,
            description: description,
            categories: categories,
            decl: decl,
            infix: infix,
            relation: isRelation,
            nondeterministic: nondeterministic,
            deprecated: deprecated,
            canSkipBctx: canSkipBctx
        )
    }

    /// Creates a copy with categories set
    public func categories(_ categories: [String]) -> BuiltinMetadata {
        return BuiltinMetadata(
            name: name,
            description: description,
            categories: categories,
            decl: decl,
            infix: infix,
            relation: relation,
            nondeterministic: nondeterministic,
            deprecated: deprecated,
            canSkipBctx: canSkipBctx
        )
    }
}

// MARK: - Convenience Factory Functions

extension BuiltinMetadata {

    /// Creates a simple function builtin
    public static func function(
        _ name: String,
        description: String? = nil,
        args: TypeSystem.RegoType...,
        result: TypeSystem.RegoType? = nil
    ) -> BuiltinMetadata {
        return BuiltinMetadata(
            name: name,
            description: description,
            args: Array(args),
            result: result
        )
    }

    /// Creates an infix operator builtin
    public static func infix(
        _ name: String,
        operator: String,
        description: String? = nil,
        args: TypeSystem.RegoType...,
        result: TypeSystem.RegoType? = nil
    ) -> BuiltinMetadata {
        return BuiltinMetadata(
            name: name,
            infix: `operator`,
            description: description,
            args: Array(args),
            result: result
        )
    }

    /// Creates a variadic function builtin
    public static func variadic(
        _ name: String,
        description: String? = nil,
        args: [TypeSystem.RegoType] = [],
        variadic: TypeSystem.RegoType,
        result: TypeSystem.RegoType? = nil
    ) -> BuiltinMetadata {
        return BuiltinMetadata(
            name: name,
            description: description,
            args: args,
            variadic: variadic,
            result: result
        )
    }
}
