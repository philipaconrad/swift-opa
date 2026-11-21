import Foundation

/// The result of scanning raw JSON for duplicate object keys.
enum JSONKeyScan: Equatable {
    case unique
    case duplicate
    case nulByte
}

/// Scans raw UTF-8 JSON for objects with duplicate keys, without building a value tree.
///
/// Keys are decoded, escapes included, and compared as Swift `String`s, so keys that are canonically equivalent
/// (such as a precomposed "é" and "e" plus a combining accent) collide just as they merge in a Swift dictionary.
/// Values are skipped. Scanning stops at the first duplicate or NUL byte. NUL bytes are rejected because UTF-16
/// and UTF-32 input would defeat a byte-level scan, and OPA only accepts UTF-8.
///
/// The scanner doesn't validate JSON, so callers must also parse the input. Malformed escapes and lone surrogates
/// in keys decode to U+FFFD, which can make two malformed keys collide in input the parser would reject anyway.
func scanJSONObjectKeys(_ data: Data) -> JSONKeyScan {
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> JSONKeyScan in
        let bytes = raw.bindMemory(to: UInt8.self)
        // Keys of every open object, flattened. Each frame holds the index where its object's keys start,
        // or -1 for an array.
        var keys: [String] = []
        var frames: [Int] = []
        // Objects past `linearLimit` keys also get a Set, indexed by frame depth.
        var largeObjects: [Int: Set<String>] = [:]
        let linearLimit = 16
        var expectKey = false
        var i = 0

        while i < bytes.count {
            switch bytes[i] {
            case 0:
                return .nulByte
            case UInt8(ascii: "{"):
                frames.append(keys.count)
                expectKey = true
            case UInt8(ascii: "["):
                frames.append(-1)
                expectKey = false
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                if let start = frames.popLast(), start >= 0 {
                    keys.removeSubrange(start...)
                    if !largeObjects.isEmpty {
                        largeObjects[frames.count] = nil
                    }
                }
                expectKey = false
            case UInt8(ascii: ","):
                // Strings inside arrays aren't keys, which the frame check below handles.
                expectKey = true
            case UInt8(ascii: "\""):
                // Find the closing quote, noting whether the string needs more than UTF-8 decoding.
                let start = i + 1
                var end = start
                var plain = true
                while end < bytes.count, bytes[end] != UInt8(ascii: "\"") {
                    if bytes[end] == 0 {
                        return .nulByte
                    }
                    if bytes[end] == UInt8(ascii: "\\") {
                        plain = false
                        end += 1
                        if end < bytes.count, bytes[end] == 0 {
                            return .nulByte
                        }
                    }
                    end += 1
                }
                end = min(end, bytes.count)
                if expectKey, let frameStart = frames.last, frameStart >= 0 {
                    let contents = UnsafeBufferPointer(rebasing: bytes[start..<end])
                    let key = plain ? String(decoding: contents, as: UTF8.self) : decodeJSONStringContents(contents)
                    let depth = frames.count - 1
                    let count = keys.count - frameStart
                    if count < linearLimit {
                        if keys[frameStart...].contains(key) {
                            return .duplicate
                        }
                        if count + 1 == linearLimit {
                            largeObjects[depth] = Set(keys[frameStart...])
                            largeObjects[depth]!.insert(key)
                        }
                    } else if largeObjects[depth]!.insert(key).inserted == false {
                        return .duplicate
                    }
                    keys.append(key)
                }
                expectKey = false
                i = end
            default:
                break
            }
            i += 1
        }
        return .unique
    }
}

/// Decodes the contents of a JSON string literal, without its quotes.
/// Malformed escapes and lone surrogates become U+FFFD.
private func decodeJSONStringContents(_ bytes: UnsafeBufferPointer<UInt8>) -> String {
    var out: [UInt8] = []
    out.reserveCapacity(bytes.count)

    func hex4(at index: Int) -> UInt32? {
        guard index + 4 <= bytes.count else {
            return nil
        }
        var value: UInt32 = 0
        for byte in bytes[index..<index + 4] {
            let digit: UInt8
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
            default: return nil
            }
            value = value << 4 | UInt32(digit)
        }
        return value
    }

    func append(_ scalar: Unicode.Scalar) {
        out.append(contentsOf: String(scalar).utf8)
    }

    var i = 0
    while i < bytes.count {
        let byte = bytes[i]
        guard byte == UInt8(ascii: "\\"), i + 1 < bytes.count else {
            out.append(byte)
            i += 1
            continue
        }
        let escape = bytes[i + 1]
        i += 2
        switch escape {
        case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(escape)
        case UInt8(ascii: "b"): out.append(0x08)
        case UInt8(ascii: "f"): out.append(0x0C)
        case UInt8(ascii: "n"): out.append(0x0A)
        case UInt8(ascii: "r"): out.append(0x0D)
        case UInt8(ascii: "t"): out.append(0x09)
        case UInt8(ascii: "u"):
            guard let high = hex4(at: i) else {
                append("\u{FFFD}")
                continue
            }
            i += 4
            // A high surrogate escape followed by a low surrogate escape encodes one scalar.
            if (0xD800...0xDBFF).contains(high), i + 6 <= bytes.count, bytes[i] == UInt8(ascii: "\\"),
                bytes[i + 1] == UInt8(ascii: "u"), let low = hex4(at: i + 2), (0xDC00...0xDFFF).contains(low)
            {
                i += 6
                append(Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00))!)
            } else {
                append(Unicode.Scalar(high) ?? "\u{FFFD}")
            }
        default:
            append("\u{FFFD}")
        }
    }
    return String(decoding: out, as: UTF8.self)
}
