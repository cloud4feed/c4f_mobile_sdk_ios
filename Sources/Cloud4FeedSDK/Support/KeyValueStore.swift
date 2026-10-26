import Foundation

/// Minimal key-value storage. The SDK uses `UserDefaults` suites in the app; tests use `InMemoryStore`.
protocol KeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeAll()
}

extension KeyValueStore {
    func string(forKey key: String) -> String? {
        object(forKey: key).flatMap(StoredValue.text)
    }

    func int(forKey key: String) -> Int {
        switch object(forKey: key) {
        case let value as Int: return value
        case let value as Int64: return Int(value)
        case let value as Double: return Int(value)
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value) ?? 0
        default: return 0
        }
    }

    func double(forKey key: String) -> Double {
        switch object(forKey: key) {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as Int64: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value) ?? 0
        default: return 0
        }
    }

    func bool(forKey key: String) -> Bool {
        switch object(forKey: key) {
        case let value as Bool: return value
        case let value as NSNumber: return value.boolValue
        case let value as String: return value.lowercased() == "true"
        default: return false
        }
    }
}

/// `UserDefaults` backed store. With a suite name it owns that suite and `removeAll` clears it.
final class UserDefaultsStore: KeyValueStore {
    let defaults: UserDefaults
    private let suiteName: String?

    init(suiteName: String?) {
        self.suiteName = suiteName
        self.defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    func object(forKey key: String) -> Any? {
        defaults.object(forKey: key)
    }

    func set(_ value: Any?, forKey key: String) {
        if let value = value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func removeAll() {
        // Never wipe the app's own standard defaults.
        guard let suiteName = suiteName else { return }
        defaults.removePersistentDomain(forName: suiteName)
    }
}

final class InMemoryStore: KeyValueStore {
    private var values: [String: Any]

    init(_ values: [String: Any] = [:]) {
        self.values = values
    }

    func object(forKey key: String) -> Any? { values[key] }

    func set(_ value: Any?, forKey key: String) { values[key] = value }

    func removeAll() { values.removeAll() }
}

/// Converts a stored value to text the way Android's `StorageUtils` does
/// (String, Boolean, Int, Long, Float -> text; anything else -> no value).
enum StoredValue {
    static func text(_ value: Any) -> String? {
        // Exact native types first (Linux/Windows and Swift-written values).
        if let value = value as? String { return value }
        if type(of: value) == Bool.self, let value = value as? Bool { return value ? "true" : "false" }
        if type(of: value) == Int.self, let value = value as? Int { return String(value) }
        if type(of: value) == Int64.self, let value = value as? Int64 { return String(value) }
        if type(of: value) == Double.self, let value = value as? Double { return JSONValue.format(value) }
        if type(of: value) == Float.self, let value = value as? Float { return JSONValue.format(Double(value)) }
        // UserDefaults on Apple platforms hands back NSNumber.
        if let number = value as? NSNumber {
            #if canImport(Darwin)
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            #endif
            return JSONValue.format(number.doubleValue)
        }
        return nil
    }
}
