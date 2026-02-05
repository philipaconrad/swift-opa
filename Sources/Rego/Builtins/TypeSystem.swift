import AST
import Foundation

/// Note(philipc): The file is mostly a machine translation with minor touch-ups
/// from the Rego type system defined upstream in:
///   https://github.com/open-policy-agent/opa/blob/main/v1/types/types.go
/// It allows us port over metadata and type signatures for builtin
/// functions in a way that maps strongly to the original design in Golang.

/// Namespace for Rego type system to avoid conflicts with Swift built-in types
public enum TypeSystem {

    // MARK: - Type Protocol

    public protocol RegoType: Codable, Sendable {
        var typeMarker: Swift.String { get }
        func toString() -> Swift.String
    }

    // MARK: - Basic Types

    public struct Null: RegoType {
        public let typeMarker = "null"

        public init() {}

        public func toString() -> Swift.String {
            return typeMarker
        }

        private enum CodingKeys: Swift.String, CodingKey {
            case type
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // We just verify the type matches, no other data needed
            _ = try container.decode(Swift.String.self, forKey: .type)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeMarker, forKey: .type)
        }
    }

    public struct Boolean: RegoType {
        public let typeMarker = "boolean"

        public init() {}

        public func toString() -> Swift.String {
            return typeMarker
        }

        private enum CodingKeys: Swift.String, CodingKey {
            case type
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // We just verify the type matches, no other data needed
            _ = try container.decode(Swift.String.self, forKey: .type)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeMarker, forKey: .type)
        }
    }

    public struct String: RegoType {
        public let typeMarker = "string"

        public init() {}

        public func toString() -> Swift.String {
            return typeMarker
        }

        private enum CodingKeys: Swift.String, CodingKey {
            case type
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // We just verify the type matches, no other data needed
            _ = try container.decode(Swift.String.self, forKey: .type)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeMarker, forKey: .type)
        }
    }

    public struct Number: RegoType {
        public let typeMarker = "number"

        public init() {}

        public func toString() -> Swift.String {
            return typeMarker
        }

        private enum CodingKeys: Swift.String, CodingKey {
            case type
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // We just verify the type matches, no other data needed
            _ = try container.decode(Swift.String.self, forKey: .type)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeMarker, forKey: .type)
        }
    }

    // MARK: - Any Type

    public struct `Any`: RegoType {
        public let typeMarker = "any"
        public let of: [RegoType]

        public init(_ of: RegoType...) {
            self.of = of
        }

        public init(_ of: [RegoType]) {
            self.of = of  // TODO: Do we need this? The varag constructor might be enough.
        }

        public func toString() -> Swift.String {
            if of.isEmpty {
                return typeMarker
            }
            let typeStrings = of.map { $0.toString() }
            return "\(typeMarker)<\(typeStrings.joined(separator: ", "))>"
        }

        private enum CodingKeys: Swift.String, CodingKey {
            case type
            case of
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let of = try container.decodeIfPresent([AnyRegoType].self, forKey: .of)?.map { $0.type } ?? []
            self.of = of
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeMarker, forKey: .type)
            if !of.isEmpty {
                try container.encode(of.map(AnyRegoType.init), forKey: .of)
            }
        }
    }

    // MARK: - Named Type

    public struct NamedType: RegoType {
        public let name: Swift.String
        public let description: Swift.String?
        public let type: RegoType

        public var typeMarker: Swift.String {
            return type.typeMarker
        }

        public init(name: Swift.String, type: RegoType, description: Swift.String? = nil) {
            self.name = name
            self.type = type
            self.description = description
        }

        public func toString() -> Swift.String {
            return "\(name): \(type.toString())"
        }

        private enum CodingKeys: Swift.String, CodingKey {
            case name
            case description
            case type
        }

        public init(from decoder: Decoder) throws {
            // NamedType is encoded as a merged object with the underlying type's fields plus name/description
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)

            self.name = try container.decode(Swift.String.self, forKey: DynamicCodingKey(stringValue: "name"))
            self.description = try container.decodeIfPresent(
                Swift.String.self, forKey: DynamicCodingKey(stringValue: "description"))

            // Decode the underlying type by creating a temporary encoder/decoder without name/description
            let allKeys = container.allKeys.map { $0.stringValue }
            var typeDict: [Swift.String: Any] = [:]

            for key in allKeys {
                if key != "name" && key != "description" {
                    if let value = try? container.decode(AnyCodable.self, forKey: DynamicCodingKey(stringValue: key)) {
                        typeDict[key] = value.value
                    }
                }
            }

            let typeData = try JSONSerialization.data(withJSONObject: typeDict)
            let typeDecoder = JSONDecoder()
            self.type = try typeDecoder.decode(AnyRegoType.self, from: typeData).type
        }

        public func encode(to encoder: Encoder) throws {
            // For NamedType, we need to merge the underlying type's JSON with name/description
            // Start by encoding the underlying type to get its fields
            let typeData = try JSONEncoder().encode(AnyRegoType(type))
            guard var typeDict = try JSONSerialization.jsonObject(with: typeData) as? [Swift.String: Any] else {
                throw EncodingError.invalidValue(
                    type,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "Could not encode underlying type"
                    ))
            }

            // Add our fields
            typeDict["name"] = name
            if let description = description {
                typeDict["description"] = description
            }

            // Encode the merged dictionary
            var container = encoder.singleValueContainer()
            try container.encode(AnyCodableDict(typeDict))
        }
    }

    // MARK: - Array Type

    public struct Array: RegoType {
        public let typeMarker = "array"
        public let staticTypes: [RegoType]
        public let dynamicType: RegoType?

        public init(static: [RegoType] = [], dynamic: RegoType? = nil) {
            self.staticTypes = `static`
            self.dynamicType = dynamic
        }

        public func toString() -> Swift.String {
            var result = typeMarker

            if !staticTypes.isEmpty {
                let typeStrings = staticTypes.map { $0.toString() }
                result += "<\(typeStrings.joined(separator: ", "))>"
            }

            if let dynamicType = dynamicType {
                result += "[\(dynamicType.toString())]"
            }

            return result
        }

        private enum CodingKeys: Swift.String, CodingKey {
            case type
            case `static`
            case dynamic
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.staticTypes = try container.decodeIfPresent([AnyRegoType].self, forKey: .static)?.map { $0.type } ?? []
            self.dynamicType = try container.decodeIfPresent(AnyRegoType.self, forKey: .dynamic)?.type
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeMarker, forKey: .type)

            if !staticTypes.isEmpty {
                try container.encode(staticTypes.map(AnyRegoType.init), forKey: .static)
            }

            if let dynamicType = dynamicType {
                try container.encode(AnyRegoType(dynamicType), forKey: .dynamic)
            }
        }
    }

    // MARK: - Set Type

    public struct Set: RegoType {
        public let typeMarker = "set"
        public let of: RegoType?

        public init(of: RegoType? = nil) {
            self.of = of
        }

        public func toString() -> Swift.String {
            if let of = of {
                return "\(typeMarker)[\(of.toString())]"
            }
            return typeMarker
        }

        private enum CodingKeys: Swift.String, CodingKey {
            case type
            case of
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.of = try container.decodeIfPresent(AnyRegoType.self, forKey: .of)?.type
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeMarker, forKey: .type)

            if let of = of {
                try container.encode(AnyRegoType(of), forKey: .of)
            }
        }
    }

    // MARK: - Object Properties

    public struct StaticProperty: Codable, Sendable {
        public let key: RegoValue  // Using RegoValue from AST module
        public let value: RegoType

        public init(key: RegoValue, value: RegoType) {
            self.key = key
            self.value = value
        }

        private enum CodingKeys: Swift.String, CodingKey {
            case key
            case value
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.key = try container.decode(RegoValue.self, forKey: .key)
            self.value = try container.decode(AnyRegoType.self, forKey: .value).type
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(key, forKey: .key)
            try container.encode(AnyRegoType(value), forKey: .value)
        }
    }

    public struct DynamicProperty: Codable, Sendable {
        public let key: RegoType
        public let value: RegoType

        public init(key: RegoType, value: RegoType) {
            self.key = key
            self.value = value
        }

        public func toString() -> Swift.String {
            return "\(key.toString()): \(value.toString())"
        }

        private enum CodingKeys: Swift.String, CodingKey {
            case key
            case value
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.key = try container.decode(AnyRegoType.self, forKey: .key).type
            self.value = try container.decode(AnyRegoType.self, forKey: .value).type
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(AnyRegoType(key), forKey: .key)
            try container.encode(AnyRegoType(value), forKey: .value)
        }
    }

    // MARK: - Object Type

    public struct Object: RegoType {
        public let typeMarker = "object"
        public let staticProperties: [StaticProperty]
        public let dynamicProperty: DynamicProperty?

        public init(static: [StaticProperty] = [], dynamic: DynamicProperty? = nil) {
            self.staticProperties = `static`
            self.dynamicProperty = dynamic
        }

        public func toString() -> Swift.String {
            var result = typeMarker

            if !staticProperties.isEmpty {
                let propStrings = staticProperties.map { "\($0.key): \($0.value.toString())" }
                result += "<\(propStrings.joined(separator: ", "))>"
            }

            if let dynamicProperty = dynamicProperty {
                result += "[\(dynamicProperty.toString())]"
            }

            return result
        }

        private enum CodingKeys: Swift.String, CodingKey {
            case type
            case `static`
            case dynamic
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.staticProperties = try container.decodeIfPresent([StaticProperty].self, forKey: .static) ?? []
            self.dynamicProperty = try container.decodeIfPresent(DynamicProperty.self, forKey: .dynamic)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeMarker, forKey: .type)

            if !staticProperties.isEmpty {
                try container.encode(staticProperties, forKey: .static)
            }

            if let dynamicProperty = dynamicProperty {
                try container.encode(dynamicProperty, forKey: .dynamic)
            }
        }
    }

    // MARK: - Function Type

    public struct Function: RegoType {
        public let typeMarker = "function"
        public let args: [RegoType]
        public let result: RegoType?
        public let variadic: RegoType?

        public init(args: [RegoType], result: RegoType? = nil, variadic: RegoType? = nil) {
            self.args = args
            self.result = result
            self.variadic = variadic
        }

        public func toString() -> Swift.String {
            let argStrings = args.map { $0.toString() }
            var argsStr = "(\(argStrings.joined(separator: ", "))"

            if let variadic = variadic {
                if !args.isEmpty {
                    argsStr += ", "
                }
                argsStr += "\(variadic.toString())..."
            }
            argsStr += ")"

            if let result = result {
                return "\(argsStr) => \(result.toString())"
            }

            return argsStr
        }

        private enum CodingKeys: Swift.String, CodingKey {
            case type
            case args
            case result
            case variadic
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.args = try container.decodeIfPresent([AnyRegoType].self, forKey: .args)?.map { $0.type } ?? []
            self.result = try container.decodeIfPresent(AnyRegoType.self, forKey: .result)?.type
            self.variadic = try container.decodeIfPresent(AnyRegoType.self, forKey: .variadic)?.type
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeMarker, forKey: .type)

            if !args.isEmpty {
                try container.encode(args.map(AnyRegoType.init), forKey: .args)
            }

            if let result = result {
                try container.encode(AnyRegoType(result), forKey: .result)
            }

            if let variadic = variadic {
                try container.encode(AnyRegoType(variadic), forKey: .variadic)
            }
        }
    }
}

// MARK: - Helper Types for Codable Support

/// Type-erased wrapper for RegoType to support heterogeneous collections
public struct AnyRegoType: Codable {
    public let type: TypeSystem.RegoType

    public init(_ type: TypeSystem.RegoType) {
        self.type = type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let typeKey = DynamicCodingKey(stringValue: "type")
        let typeMarker = try container.decode(Swift.String.self, forKey: typeKey)

        switch typeMarker {
        case "null":
            self.type = try TypeSystem.Null(from: decoder)
        case "boolean":
            self.type = try TypeSystem.Boolean(from: decoder)
        case "string":
            self.type = try TypeSystem.String(from: decoder)
        case "number":
            self.type = try TypeSystem.Number(from: decoder)
        case "array":
            self.type = try TypeSystem.Array(from: decoder)
        case "object":
            self.type = try TypeSystem.Object(from: decoder)
        case "set":
            self.type = try TypeSystem.Set(from: decoder)
        case "any":
            self.type = try TypeSystem.Any(from: decoder)
        case "function":
            self.type = try TypeSystem.Function(from: decoder)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "Unknown type marker: \(typeMarker)")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try type.encode(to: encoder)
    }
}

// MARK: - Helper Types

struct DynamicCodingKey: CodingKey {
    var stringValue: Swift.String
    var intValue: Int?

    init(stringValue: Swift.String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

struct AnyCodableDict: Codable {
    let value: [Swift.String: Any]

    init(_ value: [Swift.String: Any]) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var result: [Swift.String: Any] = [:]

        for key in container.allKeys {
            if let value = try? container.decode(AnyCodable.self, forKey: key) {
                result[key.stringValue] = value.value
            }
        }

        self.value = result
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)

        for (key, value) in self.value {
            try container.encode(AnyCodable(value), forKey: DynamicCodingKey(stringValue: key))
        }
    }
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let string = try? container.decode(Swift.String.self) {
            value = string
        } else if let number = try? container.decode(Double.self) {
            value = number
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([Swift.String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if value is NSNull {
            try container.encodeNil()
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let string = value as? Swift.String {
            try container.encode(string)
        } else if let number = value as? Double {
            try container.encode(number)
        } else if let array = value as? [Any] {
            try container.encode(array.map(AnyCodable.init))
        } else if let dict = value as? [Swift.String: Any] {
            try container.encode(dict.mapValues(AnyCodable.init))
        } else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

// MARK: - Convenience Factory Functions

extension TypeSystem {
    /// Factory functions for common type creations (matching Go API)
    public static func newNull() -> Null { Null() }
    public static func newBoolean() -> Boolean { Boolean() }
    public static func newString() -> String { String() }
    public static func newNumber() -> Number { Number() }
    public static func newAny(_ of: RegoType...) -> `Any` { `Any`(of) }
    public static func newArray(static: [RegoType] = [], dynamic: RegoType? = nil) -> Array {
        Array(static: `static`, dynamic: dynamic)
    }
    public static func newSet(of: RegoType? = nil) -> Set { Set(of: of) }
    public static func newObject(static: [StaticProperty] = [], dynamic: DynamicProperty? = nil) -> Object {
        Object(static: `static`, dynamic: dynamic)
    }
    public static func newFunction(args: [RegoType], result: RegoType? = nil, variadic: RegoType? = nil) -> Function {
        Function(args: args, result: result, variadic: variadic)
    }
    public static func named(_ name: Swift.String, _ type: RegoType, description: Swift.String? = nil) -> NamedType {
        NamedType(name: name, type: type, description: description)
    }
    public static func newStaticProperty(key: RegoValue, value: RegoType) -> StaticProperty {
        StaticProperty(key: key, value: value)
    }
    public static func newDynamicProperty(key: RegoType, value: RegoType) -> DynamicProperty {
        DynamicProperty(key: key, value: value)
    }

    // Common type instances (matching Go variables)
    public static let null = newNull()
    public static let boolean = newBoolean()
    public static let string = newString()
    public static let number = newNumber()
    public static let any = newAny()

    // Common set types
    public static let setOfAny = newSet(of: any)
    public static let setOfString = newSet(of: string)
    public static let setOfNumber = newSet(of: number)
}
