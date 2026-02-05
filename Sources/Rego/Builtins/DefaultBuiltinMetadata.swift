import AST
import Foundation

extension BuiltinMetadata {
    /// Metadata entries for all of the Rego builtin functions we support.
    internal static var defaultBuiltinMetadata: [String: BuiltinMetadata] {
        return [
            // Aggregates
            "count": BuiltinMetadata(
                name: "count",
                description:
                    "Count takes a collection or string and returns the number of elements (or characters) in it.",
                categories: ["aggregates"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "collection",
                            TypeSystem.newAny(
                                TypeSystem.setOfAny,
                                TypeSystem.newArray(dynamic: TypeSystem.any),
                                TypeSystem.newObject(
                                    dynamic: TypeSystem.newDynamicProperty(key: TypeSystem.any, value: TypeSystem.any)),
                                TypeSystem.string
                            ), description: "the set/array/object/string to be counted")
                    ],
                    result: TypeSystem.named(
                        "n", TypeSystem.number,
                        description: "the count of elements, key/val pairs, or characters, respectively.")
                ),
                canSkipBctx: true
            ),

            "max": BuiltinMetadata(
                name: "max",
                description: "Returns the maximum value in a collection.",
                categories: ["aggregates"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "collection",
                            TypeSystem.newAny(
                                TypeSystem.setOfAny,
                                TypeSystem.newArray(dynamic: TypeSystem.any)
                            ), description: "the set or array to be searched")
                    ],
                    result: TypeSystem.named("n", TypeSystem.any, description: "the maximum of all elements")
                ),
                canSkipBctx: true
            ),

            "min": BuiltinMetadata(
                name: "min",
                description: "Returns the minimum value in a collection.",
                categories: ["aggregates"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "collection",
                            TypeSystem.newAny(
                                TypeSystem.setOfAny,
                                TypeSystem.newArray(dynamic: TypeSystem.any)
                            ), description: "the set or array to be searched")
                    ],
                    result: TypeSystem.named("n", TypeSystem.any, description: "the minimum of all elements")
                ),
                canSkipBctx: true
            ),

            "product": BuiltinMetadata(
                name: "product",
                description: "Multiplies elements of an array or set of numbers",
                categories: ["aggregates"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "collection",
                            TypeSystem.newAny(
                                TypeSystem.setOfNumber,
                                TypeSystem.newArray(dynamic: TypeSystem.number)
                            ), description: "the set or array of numbers to multiply")
                    ],
                    result: TypeSystem.named("n", TypeSystem.number, description: "the product of all elements")
                ),
                canSkipBctx: true
            ),

            "sort": BuiltinMetadata(
                name: "sort",
                description: "Returns a sorted array.",
                categories: ["aggregates"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "collection",
                            TypeSystem.newAny(
                                TypeSystem.newArray(dynamic: TypeSystem.any),
                                TypeSystem.setOfAny
                            ), description: "the array or set to be sorted")
                    ],
                    result: TypeSystem.named(
                        "n", TypeSystem.newArray(dynamic: TypeSystem.any), description: "the sorted array")
                ),
                canSkipBctx: true
            ),

            "sum": BuiltinMetadata(
                name: "sum",
                description: "Sums elements of an array or set of numbers.",
                categories: ["aggregates"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "collection",
                            TypeSystem.newAny(
                                TypeSystem.setOfNumber,
                                TypeSystem.newArray(dynamic: TypeSystem.number)
                            ), description: "the set or array of numbers to sum")
                    ],
                    result: TypeSystem.named("n", TypeSystem.number, description: "the sum of all elements")
                ),
                canSkipBctx: true
            ),

            // Arithmetic
            "plus": BuiltinMetadata(
                name: "plus",
                description: "Plus adds two numbers together.",
                categories: ["numbers"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.number),
                        TypeSystem.named("y", TypeSystem.number),
                    ],
                    result: TypeSystem.named("z", TypeSystem.number, description: "the sum of `x` and `y`")
                ),
                infix: "+",
                canSkipBctx: true
            ),

            "minus": BuiltinMetadata(
                name: "minus",
                description:
                    "Minus subtracts the second number from the first number or computes the difference between two sets.",
                categories: ["sets", "numbers"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.newAny(TypeSystem.number, TypeSystem.setOfAny)),
                        TypeSystem.named("y", TypeSystem.newAny(TypeSystem.number, TypeSystem.setOfAny)),
                    ],
                    result: TypeSystem.named(
                        "z", TypeSystem.newAny(TypeSystem.number, TypeSystem.setOfAny),
                        description: "the difference of `x` and `y`")
                ),
                infix: "-",
                canSkipBctx: true
            ),

            "mul": BuiltinMetadata(
                name: "mul",
                description: "Multiplies two numbers.",
                categories: ["numbers"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.number),
                        TypeSystem.named("y", TypeSystem.number),
                    ],
                    result: TypeSystem.named("z", TypeSystem.number, description: "the product of `x` and `y`")
                ),
                infix: "*",
                canSkipBctx: true
            ),

            "div": BuiltinMetadata(
                name: "div",
                description: "Divides the first number by the second number.",
                categories: ["numbers"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.number, description: "the dividend"),
                        TypeSystem.named("y", TypeSystem.number, description: "the divisor"),
                    ],
                    result: TypeSystem.named("z", TypeSystem.number, description: "the result of `x` divided by `y`")
                ),
                infix: "/",
                canSkipBctx: true
            ),

            "round": BuiltinMetadata(
                name: "round",
                description: "Rounds the number to the nearest integer.",
                categories: ["numbers"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.number, description: "the number to round")
                    ],
                    result: TypeSystem.named("y", TypeSystem.number, description: "the result of rounding `x`")
                ),
                canSkipBctx: true
            ),

            "ceil": BuiltinMetadata(
                name: "ceil",
                description: "Rounds the number _up_ to the nearest integer.",
                categories: ["numbers"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.number, description: "the number to round")
                    ],
                    result: TypeSystem.named("y", TypeSystem.number, description: "the result of rounding `x` _up_")
                ),
                canSkipBctx: true
            ),

            "floor": BuiltinMetadata(
                name: "floor",
                description: "Rounds the number _down_ to the nearest integer.",
                categories: ["numbers"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.number, description: "the number to round")
                    ],
                    result: TypeSystem.named("y", TypeSystem.number, description: "the result of rounding `x` _down_")
                ),
                canSkipBctx: true
            ),

            "abs": BuiltinMetadata(
                name: "abs",
                description: "Returns the number without its sign.",
                categories: ["numbers"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "x", TypeSystem.number, description: "the number to take the absolute value of")
                    ],
                    result: TypeSystem.named("y", TypeSystem.number, description: "the absolute value of `x`")
                ),
                canSkipBctx: true
            ),

            "rem": BuiltinMetadata(
                name: "rem",
                description: "Returns the remainder for of `x` divided by `y`, for `y != 0`.",
                categories: ["numbers"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.number),
                        TypeSystem.named("y", TypeSystem.number),
                    ],
                    result: TypeSystem.named("z", TypeSystem.number, description: "the remainder")
                ),
                infix: "%",
                canSkipBctx: true
            ),

            // Array
            "array.concat": BuiltinMetadata(
                name: "array.concat",
                description: "Concatenates two arrays.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "x", TypeSystem.newArray(dynamic: TypeSystem.any), description: "the first array"),
                        TypeSystem.named(
                            "y", TypeSystem.newArray(dynamic: TypeSystem.any), description: "the second array"),
                    ],
                    result: TypeSystem.named(
                        "z", TypeSystem.newArray(dynamic: TypeSystem.any),
                        description: "the concatenation of `x` and `y`")
                ),
                canSkipBctx: true
            ),

            "array.reverse": BuiltinMetadata(
                name: "array.reverse",
                description: "Returns the reverse of a given array.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "arr", TypeSystem.newArray(dynamic: TypeSystem.any), description: "the array to be reversed"
                        )
                    ],
                    result: TypeSystem.named(
                        "rev", TypeSystem.newArray(dynamic: TypeSystem.any),
                        description: "an array containing the elements of `arr` in reverse order")
                ),
                canSkipBctx: true
            ),

            "array.slice": BuiltinMetadata(
                name: "array.slice",
                description:
                    "Returns a slice of a given array. If `start` is greater or equal than `stop`, `slice` is `[]`.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "arr", TypeSystem.newArray(dynamic: TypeSystem.any), description: "the array to be sliced"),
                        TypeSystem.named(
                            "start", TypeSystem.number,
                            description: "the start index of the returned slice; if less than zero, it's clamped to 0"),
                        TypeSystem.named(
                            "stop", TypeSystem.number,
                            description:
                                "the stop index of the returned slice; if larger than `count(arr)`, it's clamped to `count(arr)`"
                        ),
                    ],
                    result: TypeSystem.named(
                        "slice", TypeSystem.newArray(dynamic: TypeSystem.any),
                        description:
                            "the subslice of `array`, from `start` to `end`, including `arr[start]`, but excluding `arr[end]`"
                    )
                ),
                canSkipBctx: true
            ),

            // Bits
            "bits.and": BuiltinMetadata(
                name: "bits.and",
                description: "Returns the bitwise \"AND\" of two integers.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.number, description: "the first integer"),
                        TypeSystem.named("y", TypeSystem.number, description: "the second integer"),
                    ],
                    result: TypeSystem.named("z", TypeSystem.number, description: "the bitwise AND of `x` and `y`")
                ),
                canSkipBctx: true
            ),

            "bits.lsh": BuiltinMetadata(
                name: "bits.lsh",
                description: "Returns a new integer with its bits shifted `s` bits to the left.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.number, description: "the integer to shift"),
                        TypeSystem.named("s", TypeSystem.number, description: "the number of bits to shift"),
                    ],
                    result: TypeSystem.named(
                        "z", TypeSystem.number, description: "the result of shifting `x` `s` bits to the left")
                ),
                canSkipBctx: true
            ),

            "bits.negate": BuiltinMetadata(
                name: "bits.negate",
                description: "Returns the bitwise negation (flip) of an integer.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.number, description: "the integer to negate")
                    ],
                    result: TypeSystem.named("z", TypeSystem.number, description: "the bitwise negation of `x`")
                ),
                canSkipBctx: true
            ),

            "bits.or": BuiltinMetadata(
                name: "bits.or",
                description: "Returns the bitwise \"OR\" of two integers.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.number, description: "the first integer"),
                        TypeSystem.named("y", TypeSystem.number, description: "the second integer"),
                    ],
                    result: TypeSystem.named("z", TypeSystem.number, description: "the bitwise OR of `x` and `y`")
                ),
                canSkipBctx: true
            ),

            "bits.rsh": BuiltinMetadata(
                name: "bits.rsh",
                description: "Returns a new integer with its bits shifted `s` bits to the right.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.number, description: "the integer to shift"),
                        TypeSystem.named("s", TypeSystem.number, description: "the number of bits to shift"),
                    ],
                    result: TypeSystem.named(
                        "z", TypeSystem.number, description: "the result of shifting `x` `s` bits to the right")
                ),
                canSkipBctx: true
            ),

            "bits.xor": BuiltinMetadata(
                name: "bits.xor",
                description: "Returns the bitwise \"XOR\" (exclusive-or) of two integers.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.number, description: "the first integer"),
                        TypeSystem.named("y", TypeSystem.number, description: "the second integer"),
                    ],
                    result: TypeSystem.named("z", TypeSystem.number, description: "the bitwise XOR of `x` and `y`")
                ),
                canSkipBctx: true
            ),

            // Collections
            "internal.member_2": BuiltinMetadata(
                name: "internal.member_2",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.any,
                        TypeSystem.any,
                    ],
                    result: TypeSystem.boolean
                ),
                infix: "in",
                canSkipBctx: true
            ),

            "internal.member_3": BuiltinMetadata(
                name: "internal.member_3",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.any,
                        TypeSystem.any,
                        TypeSystem.any,
                    ],
                    result: TypeSystem.boolean
                ),
                infix: "in",
                canSkipBctx: true
            ),

            // Comparison
            "gt": BuiltinMetadata(
                name: "gt",
                categories: ["comparison"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.any),
                        TypeSystem.named("y", TypeSystem.any),
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean, description: "true if `x` is greater than `y`; false otherwise")
                ),
                infix: ">",
                canSkipBctx: true
            ),

            "gte": BuiltinMetadata(
                name: "gte",
                categories: ["comparison"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.any),
                        TypeSystem.named("y", TypeSystem.any),
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean,
                        description: "true if `x` is greater or equal to `y`; false otherwise")
                ),
                infix: ">=",
                canSkipBctx: true
            ),

            "lt": BuiltinMetadata(
                name: "lt",
                categories: ["comparison"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.any),
                        TypeSystem.named("y", TypeSystem.any),
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean, description: "true if `x` is less than `y`; false otherwise")
                ),
                infix: "<",
                canSkipBctx: true
            ),

            "lte": BuiltinMetadata(
                name: "lte",
                categories: ["comparison"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.any),
                        TypeSystem.named("y", TypeSystem.any),
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean,
                        description: "true if `x` is less than or equal to `y`; false otherwise")
                ),
                infix: "<=",
                canSkipBctx: true
            ),

            "neq": BuiltinMetadata(
                name: "neq",
                categories: ["comparison"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.any),
                        TypeSystem.named("y", TypeSystem.any),
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean, description: "true if `x` is not equal to `y`; false otherwise")
                ),
                infix: "!=",
                canSkipBctx: true
            ),

            "equal": BuiltinMetadata(
                name: "equal",
                categories: ["comparison"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.any),
                        TypeSystem.named("y", TypeSystem.any),
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean, description: "true if `x` is equal to `y`; false otherwise")
                ),
                infix: "==",
                canSkipBctx: true
            ),

            // Conversions
            "to_number": BuiltinMetadata(
                name: "to_number",
                description:
                    "Converts a string, bool, or number value to a number: Strings are converted to numbers using `strconv.Atoi`, Boolean `false` is converted to 0 and `true` is converted to 1.",
                categories: ["conversions"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "x",
                            TypeSystem.newAny(
                                TypeSystem.number,
                                TypeSystem.string,
                                TypeSystem.boolean,
                                TypeSystem.null
                            ), description: "value to convert")
                    ],
                    result: TypeSystem.named("num", TypeSystem.number, description: "the numeric representation of `x`")
                ),
                canSkipBctx: true
            ),

            // Cryptography
            "crypto.hmac.equal": BuiltinMetadata(
                name: "crypto.hmac.equal",
                description:
                    "Returns a boolean representing the result of comparing two MACs for equality without leaking timing information.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("mac1", TypeSystem.string, description: "mac1 to compare"),
                        TypeSystem.named("mac2", TypeSystem.string, description: "mac2 to compare"),
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean, description: "`true` if the MACs are equals, `false` otherwise")
                ),
                canSkipBctx: true
            ),

            "crypto.hmac.md5": BuiltinMetadata(
                name: "crypto.hmac.md5",
                description: "Returns a string representing the MD5 HMAC of the input message using the input key.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "input string"),
                        TypeSystem.named("key", TypeSystem.string, description: "key to use"),
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "MD5-HMAC of `x`")
                ),
                canSkipBctx: true
            ),

            "crypto.hmac.sha1": BuiltinMetadata(
                name: "crypto.hmac.sha1",
                description: "Returns a string representing the SHA1 HMAC of the input message using the input key.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "input string"),
                        TypeSystem.named("key", TypeSystem.string, description: "key to use"),
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "SHA1-HMAC of `x`")
                ),
                canSkipBctx: true
            ),

            "crypto.hmac.sha256": BuiltinMetadata(
                name: "crypto.hmac.sha256",
                description: "Returns a string representing the SHA256 HMAC of the input message using the input key.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "input string"),
                        TypeSystem.named("key", TypeSystem.string, description: "key to use"),
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "SHA256-HMAC of `x`")
                ),
                canSkipBctx: true
            ),

            "crypto.hmac.sha512": BuiltinMetadata(
                name: "crypto.hmac.sha512",
                description: "Returns a string representing the SHA512 HMAC of the input message using the input key.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "input string"),
                        TypeSystem.named("key", TypeSystem.string, description: "key to use"),
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "SHA512-HMAC of `x`")
                ),
                canSkipBctx: true
            ),

            "crypto.md5": BuiltinMetadata(
                name: "crypto.md5",
                description: "Returns a string representing the input string hashed with the MD5 function",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "input string")
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "MD5-hash of `x`")
                ),
                canSkipBctx: true
            ),

            "crypto.sha1": BuiltinMetadata(
                name: "crypto.sha1",
                description: "Returns a string representing the input string hashed with the SHA1 function",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "input string")
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "SHA1-hash of `x`")
                ),
                canSkipBctx: true
            ),

            "crypto.sha256": BuiltinMetadata(
                name: "crypto.sha256",
                description: "Returns a string representing the input string hashed with the SHA256 function",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "input string")
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "SHA256-hash of `x`")
                ),
                canSkipBctx: true
            ),

            // Encoding
            "base64.encode": BuiltinMetadata(
                name: "base64.encode",
                description: "Serializes the input string into base64 encoding.",
                categories: ["encoding"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "string to encode")
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "base64 serialization of `x`")
                ),
                canSkipBctx: true
            ),

            "base64.decode": BuiltinMetadata(
                name: "base64.decode",
                description: "Deserializes the base64 encoded input string.",
                categories: ["encoding"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "string to decode")
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "base64 deserialization of `x`")
                ),
                canSkipBctx: true
            ),

            "base64.is_valid": BuiltinMetadata(
                name: "base64.is_valid",
                description: "Verifies the input string is base64 encoded.",
                categories: ["encoding"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "string to check")
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean,
                        description: "`true` if `x` is valid base64 encoded value, `false` otherwise")
                ),
                canSkipBctx: true
            ),

            "base64url.encode": BuiltinMetadata(
                name: "base64url.encode",
                description: "Serializes the input string into base64url encoding.",
                categories: ["encoding"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "string to encode")
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "base64url serialization of `x`")
                ),
                canSkipBctx: true
            ),

            "base64url.encode_no_pad": BuiltinMetadata(
                name: "base64url.encode_no_pad",
                description: "Serializes the input string into base64url encoding without padding.",
                categories: ["encoding"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "string to encode")
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "base64url serialization of `x`")
                ),
                canSkipBctx: true
            ),

            "base64url.decode": BuiltinMetadata(
                name: "base64url.decode",
                description: "Deserializes the base64url encoded input string.",
                categories: ["encoding"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "string to decode")
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "base64url deserialization of `x`")
                ),
                canSkipBctx: true
            ),

            "hex.encode": BuiltinMetadata(
                name: "hex.encode",
                description: "Serializes the input string using hex-encoding.",
                categories: ["encoding"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "string to encode")
                    ],
                    result: TypeSystem.named(
                        "y", TypeSystem.string, description: "serialization of `x` using hex-encoding")
                ),
                canSkipBctx: true
            ),

            "hex.decode": BuiltinMetadata(
                name: "hex.decode",
                description: "Deserializes the hex-encoded input string.",
                categories: ["encoding"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "a hex-encoded string")
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "deserialized from `x`")
                ),
                canSkipBctx: true
            ),

            // Numbers
            "numbers.range": BuiltinMetadata(
                name: "numbers.range",
                description:
                    "Returns an array of numbers in the given (inclusive) range. If `a==b`, then `range == [a]`; if `a > b`, then `range` is in descending order.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("a", TypeSystem.number, description: "the start of the range"),
                        TypeSystem.named("b", TypeSystem.number, description: "the end of the range (inclusive)"),
                    ],
                    result: TypeSystem.named(
                        "range", TypeSystem.newArray(dynamic: TypeSystem.number),
                        description: "the range between `a` and `b`")
                ),
                canSkipBctx: false
            ),

            "numbers.range_step": BuiltinMetadata(
                name: "numbers.range_step",
                description:
                    "Returns an array of numbers in the given (inclusive) range incremented by a positive step.\nIf \"a==b\", then \"range == [a]\"; if \"a > b\", then \"range\" is in descending order.\nIf the provided \"step\" is less then 1, an error will be thrown.\nIf \"b\" is not in the range of the provided \"step\", \"b\" won't be included in the result.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("a", TypeSystem.number, description: "the start of the range"),
                        TypeSystem.named("b", TypeSystem.number, description: "the end of the range (inclusive)"),
                        TypeSystem.named(
                            "step", TypeSystem.number, description: "the step between numbers in the range"),
                    ],
                    result: TypeSystem.named(
                        "range", TypeSystem.newArray(dynamic: TypeSystem.number),
                        description: "the range between `a` and `b` in `step` increments")
                ),
                canSkipBctx: false
            ),

            // Objects
            "object.get": BuiltinMetadata(
                name: "object.get",
                description:
                    "Returns value of an object's key if present, otherwise a default. If the supplied `key` is an `array`, then `object.get` will search through a nested object or array using each key in turn. For example: `object.get({\"a\": [{ \"b\": true }]}, [\"a\", 0, \"b\"], false)` results in `true`.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "object",
                            TypeSystem.newObject(
                                dynamic: TypeSystem.newDynamicProperty(key: TypeSystem.any, value: TypeSystem.any)),
                            description: "object to get `key` from"),
                        TypeSystem.named("key", TypeSystem.any, description: "key to lookup in `object`"),
                        TypeSystem.named("default", TypeSystem.any, description: "default to use when lookup fails"),
                    ],
                    result: TypeSystem.named(
                        "value", TypeSystem.any, description: "`object[key]` if present, otherwise `default`")
                ),
                canSkipBctx: true
            ),

            "object.keys": BuiltinMetadata(
                name: "object.keys",
                description:
                    "Returns a set of an object's keys. For example: `object.keys({\"a\": 1, \"b\": true, \"c\": \"d\")` results in `{\"a\", \"b\", \"c\"}`.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "object",
                            TypeSystem.newObject(
                                dynamic: TypeSystem.newDynamicProperty(key: TypeSystem.any, value: TypeSystem.any)),
                            description: "object to get keys from")
                    ],
                    result: TypeSystem.named("value", TypeSystem.setOfAny, description: "set of `object`'s keys")
                ),
                canSkipBctx: true
            ),

            "object.union": BuiltinMetadata(
                name: "object.union",
                description:
                    "Creates a new object of the asymmetric union of two objects. For example: `object.union({\"a\": 1, \"b\": 2, \"c\": {\"d\": 3}}, {\"a\": 7, \"c\": {\"d\": 4, \"e\": 5}})` will result in `{\"a\": 7, \"b\": 2, \"c\": {\"d\": 4, \"e\": 5}}`.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "a",
                            TypeSystem.newObject(
                                dynamic: TypeSystem.newDynamicProperty(key: TypeSystem.any, value: TypeSystem.any)),
                            description: "left-hand object"),
                        TypeSystem.named(
                            "b",
                            TypeSystem.newObject(
                                dynamic: TypeSystem.newDynamicProperty(key: TypeSystem.any, value: TypeSystem.any)),
                            description: "right-hand object"),
                    ],
                    result: TypeSystem.named(
                        "output", TypeSystem.any,
                        description:
                            "a new object which is the result of an asymmetric recursive union of two objects where conflicts are resolved by choosing the key from the right-hand object `b`"
                    )
                ),
                canSkipBctx: true
            ),

            "object.union_n": BuiltinMetadata(
                name: "object.union_n",
                description:
                    "Creates a new object that is the asymmetric union of all objects merged from left to right. For example: `object.union_n([{\"a\": 1}, {\"b\": 2}, {\"a\": 3}])` will result in `{\"b\": 2, \"a\": 3}`.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "objects",
                            TypeSystem.newArray(
                                dynamic: TypeSystem.newObject(
                                    dynamic: TypeSystem.newDynamicProperty(key: TypeSystem.any, value: TypeSystem.any))),
                            description: "list of objects to merge")
                    ],
                    result: TypeSystem.named(
                        "output", TypeSystem.any,
                        description:
                            "asymmetric recursive union of all objects in `objects`, merged from left to right, where conflicts are resolved by choosing the key from the right-hand object"
                    )
                ),
                canSkipBctx: true
            ),

            // Rand
            "rand.intn": BuiltinMetadata(
                name: "rand.intn",
                description:
                    "Returns a random integer between `0` and `n` (`n` exclusive). If `n` is `0`, then `y` is always `0`. For any given argument pair (`str`, `n`), the output will be consistent throughout a query evaluation.",
                categories: ["numbers"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("str", TypeSystem.string, description: "seed string for the random number"),
                        TypeSystem.named(
                            "n", TypeSystem.number, description: "upper bound of the random number (exclusive)"),
                    ],
                    result: TypeSystem.named(
                        "y", TypeSystem.number, description: "random integer in the range `[0, abs(n))`")
                ),
                nondeterministic: true,
                canSkipBctx: false
            ),

            // Sets
            "and": BuiltinMetadata(
                name: "and",
                description: "Returns the intersection of two sets.",
                categories: ["sets"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.setOfAny, description: "the first set"),
                        TypeSystem.named("y", TypeSystem.setOfAny, description: "the second set"),
                    ],
                    result: TypeSystem.named("z", TypeSystem.setOfAny, description: "the intersection of `x` and `y`")
                ),
                infix: "&",
                canSkipBctx: true
            ),

            "intersection": BuiltinMetadata(
                name: "intersection",
                description: "Returns the intersection of the given input sets.",
                categories: ["sets"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "xs", TypeSystem.newSet(of: TypeSystem.setOfAny), description: "set of sets to intersect")
                    ],
                    result: TypeSystem.named("y", TypeSystem.setOfAny, description: "the intersection of all `xs` sets")
                ),
                canSkipBctx: true
            ),

            "or": BuiltinMetadata(
                name: "or",
                description: "Returns the union of two sets.",
                categories: ["sets"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.setOfAny),
                        TypeSystem.named("y", TypeSystem.setOfAny),
                    ],
                    result: TypeSystem.named("z", TypeSystem.setOfAny, description: "the union of `x` and `y`")
                ),
                infix: "|",
                canSkipBctx: true
            ),

            "union": BuiltinMetadata(
                name: "union",
                description: "Returns the union of the given input sets.",
                categories: ["sets"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "xs", TypeSystem.newSet(of: TypeSystem.setOfAny), description: "set of sets to merge")
                    ],
                    result: TypeSystem.named("y", TypeSystem.setOfAny, description: "the union of all `xs` sets")
                ),
                canSkipBctx: true
            ),

            // String
            "concat": BuiltinMetadata(
                name: "concat",
                description: "Joins a set or array of strings with a delimiter.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("delimiter", TypeSystem.string, description: "string to use as a delimiter"),
                        TypeSystem.named(
                            "collection",
                            TypeSystem.newAny(
                                TypeSystem.setOfString,
                                TypeSystem.newArray(dynamic: TypeSystem.string)
                            ), description: "strings to join"),
                    ],
                    result: TypeSystem.named("output", TypeSystem.string, description: "the joined string")
                ),
                canSkipBctx: true
            ),

            "contains": BuiltinMetadata(
                name: "contains",
                description: "Returns `true` if the search string is included in the base string",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("haystack", TypeSystem.string, description: "string to search in"),
                        TypeSystem.named("needle", TypeSystem.string, description: "substring to look for"),
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean, description: "result of the containment check")
                ),
                canSkipBctx: true
            ),

            "endswith": BuiltinMetadata(
                name: "endswith",
                description: "Returns true if the search string ends with the base string.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("search", TypeSystem.string, description: "search string"),
                        TypeSystem.named("base", TypeSystem.string, description: "base string"),
                    ],
                    result: TypeSystem.named("result", TypeSystem.boolean, description: "result of the suffix check")
                ),
                canSkipBctx: true
            ),

            "format_int": BuiltinMetadata(
                name: "format_int",
                description:
                    "Returns the string representation of the number in the given base after rounding it down to an integer value.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("number", TypeSystem.number, description: "number to format"),
                        TypeSystem.named(
                            "base", TypeSystem.number, description: "base of number representation to use"),
                    ],
                    result: TypeSystem.named("output", TypeSystem.string, description: "formatted number")
                ),
                canSkipBctx: true
            ),

            "indexof": BuiltinMetadata(
                name: "indexof",
                description: "Returns the index of a substring contained inside a string.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("haystack", TypeSystem.string, description: "string to search in"),
                        TypeSystem.named("needle", TypeSystem.string, description: "substring to look for"),
                    ],
                    result: TypeSystem.named(
                        "output", TypeSystem.number, description: "index of first occurrence, `-1` if not found")
                ),
                canSkipBctx: true
            ),

            "indexof_n": BuiltinMetadata(
                name: "indexof_n",
                description: "Returns a list of all the indexes of a substring contained inside a string.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("haystack", TypeSystem.string, description: "string to search in"),
                        TypeSystem.named("needle", TypeSystem.string, description: "substring to look for"),
                    ],
                    result: TypeSystem.named(
                        "output", TypeSystem.newArray(dynamic: TypeSystem.number),
                        description: "all indices at which `needle` occurs in `haystack`, may be empty")
                ),
                canSkipBctx: true
            ),

            "lower": BuiltinMetadata(
                name: "lower",
                description: "Returns the input string but with all characters in lower-case.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "string that is converted to lower-case")
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "lower-case of x")
                ),
                canSkipBctx: true
            ),

            "replace": BuiltinMetadata(
                name: "replace",
                description: "Replace replaces all instances of a sub-string.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "string being processed"),
                        TypeSystem.named("old", TypeSystem.string, description: "substring to replace"),
                        TypeSystem.named("new", TypeSystem.string, description: "string to replace `old` with"),
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "string with replaced substrings")
                ),
                canSkipBctx: true
            ),

            "split": BuiltinMetadata(
                name: "split",
                description: "Split returns an array containing elements of the input string split on a delimiter.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "string that is split"),
                        TypeSystem.named("delimiter", TypeSystem.string, description: "delimiter used for splitting"),
                    ],
                    result: TypeSystem.named(
                        "ys", TypeSystem.newArray(dynamic: TypeSystem.string), description: "split parts")
                ),
                canSkipBctx: true
            ),

            "sprintf": BuiltinMetadata(
                name: "sprintf",
                description: "Returns the given string, formatted.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("format", TypeSystem.string, description: "string with formatting verbs"),
                        TypeSystem.named(
                            "values", TypeSystem.newArray(dynamic: TypeSystem.any),
                            description: "arguments to format into formatting verbs"),
                    ],
                    result: TypeSystem.named(
                        "output", TypeSystem.string, description: "`format` formatted by the values in `values`")
                ),
                canSkipBctx: true
            ),

            "startswith": BuiltinMetadata(
                name: "startswith",
                description: "Returns true if the search string begins with the base string.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("search", TypeSystem.string, description: "search string"),
                        TypeSystem.named("base", TypeSystem.string, description: "base string"),
                    ],
                    result: TypeSystem.named("result", TypeSystem.boolean, description: "result of the prefix check")
                ),
                canSkipBctx: true
            ),

            "strings.count": BuiltinMetadata(
                name: "strings.count",
                description: "Returns the number of non-overlapping instances of a substring in a string.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("search", TypeSystem.string, description: "string to search in"),
                        TypeSystem.named("substring", TypeSystem.string, description: "substring to look for"),
                    ],
                    result: TypeSystem.named(
                        "output", TypeSystem.number, description: "count of occurrences, `0` if not found")
                ),
                canSkipBctx: true
            ),

            "strings.reverse": BuiltinMetadata(
                name: "strings.reverse",
                description: "Reverses a given string.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "string to reverse")
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "reversed string")
                ),
                canSkipBctx: true
            ),

            "substring": BuiltinMetadata(
                name: "substring",
                description:
                    "Returns the portion of a string for a given `offset` and a `length`. If `length < 0`, `output` is the remainder of the string.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("value", TypeSystem.string, description: "string to extract substring from"),
                        TypeSystem.named("offset", TypeSystem.number, description: "offset, must be positive"),
                        TypeSystem.named(
                            "length", TypeSystem.number, description: "length of the substring starting from `offset`"),
                    ],
                    result: TypeSystem.named(
                        "output", TypeSystem.string,
                        description: "substring of `value` from `offset`, of length `length`")
                ),
                canSkipBctx: true
            ),

            "trim": BuiltinMetadata(
                name: "trim",
                description:
                    "Returns `value` with all leading or trailing instances of the `cutset` characters removed.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("value", TypeSystem.string, description: "string to trim"),
                        TypeSystem.named(
                            "cutset", TypeSystem.string, description: "string of characters that are cut off"),
                    ],
                    result: TypeSystem.named(
                        "output", TypeSystem.string, description: "string trimmed of `cutset` characters")
                ),
                canSkipBctx: true
            ),

            "trim_left": BuiltinMetadata(
                name: "trim_left",
                description: "Returns `value` with all leading instances of the `cutset` characters removed.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("value", TypeSystem.string, description: "string to trim"),
                        TypeSystem.named(
                            "cutset", TypeSystem.string,
                            description: "string of characters that are cut off on the left"),
                    ],
                    result: TypeSystem.named(
                        "output", TypeSystem.string, description: "string left-trimmed of `cutset` characters")
                ),
                canSkipBctx: true
            ),

            "trim_prefix": BuiltinMetadata(
                name: "trim_prefix",
                description:
                    "Returns `value` without the prefix. If `value` doesn't start with `prefix`, it is returned unchanged.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("value", TypeSystem.string, description: "string to trim"),
                        TypeSystem.named("prefix", TypeSystem.string, description: "prefix to cut off"),
                    ],
                    result: TypeSystem.named("output", TypeSystem.string, description: "string with `prefix` cut off")
                ),
                canSkipBctx: true
            ),

            "trim_right": BuiltinMetadata(
                name: "trim_right",
                description: "Returns `value` with all trailing instances of the `cutset` characters removed.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("value", TypeSystem.string, description: "string to trim"),
                        TypeSystem.named(
                            "cutset", TypeSystem.string,
                            description: "string of characters that are cut off on the right"),
                    ],
                    result: TypeSystem.named(
                        "output", TypeSystem.string, description: "string right-trimmed of `cutset` characters")
                ),
                canSkipBctx: true
            ),

            "trim_space": BuiltinMetadata(
                name: "trim_space",
                description: "Return the given string with all leading and trailing white space removed.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("value", TypeSystem.string, description: "string to trim")
                    ],
                    result: TypeSystem.named(
                        "output", TypeSystem.string, description: "string leading and trailing white space cut off")
                ),
                canSkipBctx: true
            ),

            "trim_suffix": BuiltinMetadata(
                name: "trim_suffix",
                description:
                    "Returns `value` without the suffix. If `value` doesn't end with `suffix`, it is returned unchanged.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("value", TypeSystem.string, description: "string to trim"),
                        TypeSystem.named("suffix", TypeSystem.string, description: "suffix to cut off"),
                    ],
                    result: TypeSystem.named("output", TypeSystem.string, description: "string with `suffix` cut off")
                ),
                canSkipBctx: true
            ),

            "upper": BuiltinMetadata(
                name: "upper",
                description: "Returns the input string but with all characters in upper-case.",
                categories: ["strings"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "string that is converted to upper-case")
                    ],
                    result: TypeSystem.named("y", TypeSystem.string, description: "upper-case of x")
                ),
                canSkipBctx: true
            ),

            // Note: "internal.template_string" is not found upstream, so we have a basic stub for it here.
            "internal.template_string": BuiltinMetadata(
                name: "internal.template_string",
                description: "Internal utility for handling OPA's template strings.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named(
                            "parts", TypeSystem.newArray(dynamic: TypeSystem.any),
                            description: "parts of the template string, or items to stringify")
                    ],
                    result: TypeSystem.string
                ),
                canSkipBctx: true
            ),

            // Time
            "time.now_ns": BuiltinMetadata(
                name: "time.now_ns",
                description: "Returns the current time since epoch in nanoseconds.",
                decl: TypeSystem.newFunction(
                    args: [],
                    result: TypeSystem.named("now", TypeSystem.number, description: "nanoseconds since epoch")
                ),
                nondeterministic: true,
                canSkipBctx: false
            ),

            // Trace
            "trace": BuiltinMetadata(
                name: "trace",
                description:
                    "Emits `note` as a `Note` event in the query explanation. Query explanations show the exact expressions evaluated by OPA during policy execution. For example, `trace(\"Hello There!\")` includes `Note \"Hello There!\"` in the query explanation. To include variables in the message, use `sprintf`. For example, `person := \"Bob\"; trace(sprintf(\"Hello There! %v\", [person]))` will emit `Note \"Hello There! Bob\"` inside of the explanation.",
                categories: ["tracing"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("note", TypeSystem.string, description: "the note to include")
                    ],
                    result: TypeSystem.named("result", TypeSystem.boolean, description: "always `true`")
                ),
                canSkipBctx: false
            ),

            // Types
            "is_array": BuiltinMetadata(
                name: "is_array",
                description: "Returns `true` if the input value is an array.",
                categories: ["types"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.any, description: "input value")
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean, description: "`true` if `x` is an array, `false` otherwise.")
                ),
                canSkipBctx: true
            ),

            "is_boolean": BuiltinMetadata(
                name: "is_boolean",
                description: "Returns `true` if the input value is a boolean.",
                categories: ["types"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.any, description: "input value")
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean, description: "`true` if `x` is an boolean, `false` otherwise.")
                ),
                canSkipBctx: true
            ),

            "is_null": BuiltinMetadata(
                name: "is_null",
                description: "Returns `true` if the input value is null.",
                categories: ["types"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.any, description: "input value")
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean, description: "`true` if `x` is null, `false` otherwise.")
                ),
                canSkipBctx: true
            ),

            "is_number": BuiltinMetadata(
                name: "is_number",
                description: "Returns `true` if the input value is a number.",
                categories: ["types"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.any, description: "input value")
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean, description: "`true` if `x` is a number, `false` otherwise.")
                ),
                canSkipBctx: true
            ),

            "is_object": BuiltinMetadata(
                name: "is_object",
                description: "Returns true if the input value is an object",
                categories: ["types"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.any, description: "input value")
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean, description: "`true` if `x` is an object, `false` otherwise.")
                ),
                canSkipBctx: true
            ),

            "is_set": BuiltinMetadata(
                name: "is_set",
                description: "Returns `true` if the input value is a set.",
                categories: ["types"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.any, description: "input value")
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean, description: "`true` if `x` is a set, `false` otherwise.")
                ),
                canSkipBctx: true
            ),

            "is_string": BuiltinMetadata(
                name: "is_string",
                description: "Returns `true` if the input value is a string.",
                categories: ["types"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.any, description: "input value")
                    ],
                    result: TypeSystem.named(
                        "result", TypeSystem.boolean, description: "`true` if `x` is a string, `false` otherwise.")
                ),
                canSkipBctx: true
            ),

            "type_name": BuiltinMetadata(
                name: "type_name",
                description: "Returns the type of its input value.",
                categories: ["types"],
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.any, description: "input value")
                    ],
                    result: TypeSystem.named(
                        "type", TypeSystem.string,
                        description:
                            "one of \"null\", \"boolean\", \"number\", \"string\", \"array\", \"object\", \"set\"")
                ),
                canSkipBctx: true
            ),

            // Units
            "units.parse": BuiltinMetadata(
                name: "units.parse",
                description:
                    "Converts strings like \"10G\", \"5K\", \"4M\", \"1500m\", and the like into a number.\nThis number can be a non-integer, such as 1.5, 0.22, etc. Scientific notation is supported,\nallowing values such as \"1e-3K\" (1) or \"2.5e6M\" (2.5 million M).\nSupports standard metric decimal and binary SI units (e.g., K, Ki, M, Mi, G, Gi, etc.) where\nm, K, M, G, T, P, and E are treated as decimal units and Ki, Mi, Gi, Ti, Pi, and Ei are treated as\nbinary units.\nNote that 'm' and 'M' are case-sensitive to allow distinguishing between \"milli\" and \"mega\" units\nrespectively. Other units are case-insensitive.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "the unit to parse")
                    ],
                    result: TypeSystem.named("y", TypeSystem.number, description: "the parsed number")
                ),
                canSkipBctx: true
            ),

            "units.parse_bytes": BuiltinMetadata(
                name: "units.parse_bytes",
                description:
                    "Converts strings like \"10GB\", \"5K\", \"4mb\", or \"1e6KB\" into an integer number of bytes.\nSupports standard byte units (e.g., KB, KiB, etc.) where KB, MB, GB, and TB are treated as decimal\nunits, and KiB, MiB, GiB, and TiB are treated as binary units. Scientific notation is supported,\nenabling values like \"1.5e3MB\" (1500MB) or \"2e6GiB\" (2 million GiB).\nThe bytes symbol (b/B) in the unit is optional; omitting it will yield the same result (e.g., \"Mi\"\nand \"MiB\" are equivalent).",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("x", TypeSystem.string, description: "the byte unit to parse")
                    ],
                    result: TypeSystem.named("y", TypeSystem.number, description: "the parsed number")
                ),
                canSkipBctx: true
            ),

            // UUID
            "uuid.rfc4122": BuiltinMetadata(
                name: "uuid.rfc4122",
                description: "Returns a new UUIDv4.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("k", TypeSystem.string, description: "seed string")
                    ],
                    result: TypeSystem.named(
                        "output", TypeSystem.string,
                        description:
                            "a version 4 UUID; for any given `k`, the output will be consistent throughout a query evaluation"
                    )
                ),
                nondeterministic: true,
                canSkipBctx: false
            ),

            "uuid.parse": BuiltinMetadata(
                name: "uuid.parse",
                description:
                    "Parses the string value as an UUID and returns an object with the well-defined fields of the UUID if valid.",
                decl: TypeSystem.newFunction(
                    args: [
                        TypeSystem.named("uuid", TypeSystem.string, description: "UUID string to parse")
                    ],
                    result: TypeSystem.named(
                        "result",
                        TypeSystem.newObject(
                            dynamic: TypeSystem.newDynamicProperty(key: TypeSystem.string, value: TypeSystem.any)),
                        description: "Properties of UUID if valid (version, variant, etc). Undefined otherwise.")
                ),
                relation: false,
                canSkipBctx: true
            ),
        ]
    }
}
