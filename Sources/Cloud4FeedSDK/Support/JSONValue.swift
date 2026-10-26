import Foundation

/// A small JSON tree used for tolerant parsing.
///
/// Decoding goes through `JSONDecoder`, which keeps booleans and numbers apart on every platform
/// (`JSONSerialization` returns `NSNumber` for both on Apple platforms). The accessors mirror the
/// lenient `org.json` `opt*` behaviour the Android SDK relies on: a number is accepted where a
/// string is expected, `"true"`/`"false"` strings are accepted as booleans, numeric strings as numbers.
enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func serialized() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    // MARK: Accessors

    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let object) = self { return object }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let array) = self { return array }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Strings as-is, numbers and booleans as text, `null` / containers as nil (org.json `optString`).
    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return JSONValue.format(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    /// Booleans, or the strings "true"/"false" in any case (org.json `optBoolean`).
    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value):
            switch value.lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        default: return nil
        }
    }

    /// Numbers, or numeric strings (org.json `optDouble`).
    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    /// Whole part of `doubleValue` (org.json `optInt` / `optLong` truncate decimals).
    var int64Value: Int64? {
        guard let value = doubleValue, value.isFinite,
              value >= Double(Int64.min), value <= Double(Int64.max) else { return nil }
        return Int64(value.rounded(.towardZero))
    }

    var intValue: Int? {
        guard let value = int64Value, value >= Int64(Int.min), value <= Int64(Int.max) else { return nil }
        return Int(value)
    }

    /// Whole numbers without a decimal part ("5", not "5.0"), like org.json does for integers.
    static func format(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }
}

extension JSONValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Write whole numbers as integers so the cache file stays readable.
            if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
