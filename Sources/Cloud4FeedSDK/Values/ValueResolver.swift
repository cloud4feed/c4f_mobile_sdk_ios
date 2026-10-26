import Foundation

/// STORAGE source: looks a key up in an ordered list of stores and returns the first hit.
/// Default order: the SDK's own suite (written by `setUserProperty`), then `UserDefaults.standard`,
/// then any suites the app registered. The Keychain is never read.
final class StorageReader {
    private(set) var stores: [KeyValueStore]

    init(stores: [KeyValueStore]) {
        self.stores = stores
    }

    func addStore(_ store: KeyValueStore) {
        stores.append(store)
    }

    func value(forKey key: String) -> String? {
        for store in stores {
            if let value = store.string(forKey: key) { return value }
        }
        return nil
    }
}

/// Resolves values for custom parameters and exclusion rules. Both use the same lookup,
/// exactly like Android (`ExclusionRuleEvaluator.getValueFromSource` / `collectCustomParams`).
final class ValueResolver {
    let storage: StorageReader
    let device: DeviceInfoProviding
    let session: SessionTracker
    let urlParameters: URLParameterStore
    /// Install date (iOS has no install-date API: the app container's creation date is used).
    let installDate: () -> Date?
    let now: () -> Date
    let calendar: Calendar

    init(storage: StorageReader,
         device: DeviceInfoProviding,
         session: SessionTracker,
         urlParameters: URLParameterStore,
         installDate: @escaping () -> Date? = ValueResolver.appContainerCreationDate,
         now: @escaping () -> Date = Date.init,
         calendar: Calendar = .current) {
        self.storage = storage
        self.device = device
        self.session = session
        self.urlParameters = urlParameters
        self.installDate = installDate
        self.now = now
        self.calendar = calendar
    }

    /// Key used for the lookup: the configured `key`, otherwise a per-source default
    /// (TIMESTAMP `millis`, INSTALL_TIME `days`, APP_USAGE `sessions`, others the param/rule name).
    static func lookupKey(source: ValueSource, key: String?, name: String) -> String {
        if let key = key { return key }
        switch source {
        case .timestamp: return "millis"
        case .installTime: return "days"
        case .appUsage: return "sessions"
        case .storage, .device, .url, .session: return name
        }
    }

    /// Nil = the source has no value for this key.
    func value(source: ValueSource, key: String?, name: String) -> String? {
        let lookup = Self.lookupKey(source: source, key: key, name: name)
        switch source {
        case .storage: return storage.value(forKey: lookup)
        case .device: return device.value(forKey: lookup).flatMap { $0 == "unknown" ? nil : $0 }
        case .url: return urlParameters.value(forKey: lookup)
        case .timestamp: return timestampValue(lookup)
        case .session: return session.sessionValue(forKey: lookup)
        case .installTime: return installTimeValue(lookup)
        case .appUsage: return session.appUsageValue(lookup)
        }
    }

    // MARK: TIMESTAMP

    /// `millis` (default), `seconds`, `iso` (`yyyy-MM-dd HH:mm`, local time), `hour`,
    /// `day_of_week` (1 = Sunday), `day_of_month`, `month` (1-12).
    /// `timestamp` / `current_time` are the Configuration Manager labels for epoch milliseconds.
    func timestampValue(_ format: String) -> String {
        let date = now()
        let millis = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
        switch format {
        case "seconds":
            return String(millis / 1000)
        case "iso":
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: date)
        case "hour":
            return String(calendar.component(.hour, from: date))
        case "day_of_week":
            return String(calendar.component(.weekday, from: date))
        case "day_of_month":
            return String(calendar.component(.day, from: date))
        case "month":
            return String(calendar.component(.month, from: date))
        default:
            return String(millis)
        }
    }

    // MARK: INSTALL_TIME

    /// `days` (default), `hours`, `minutes` since install, or `millis` / `install_timestamp`.
    /// Nil when the install date is unknown (numeric rules then do not match).
    func installTimeValue(_ unit: String) -> String? {
        guard let install = installDate() else { return nil }
        let installMillis = Int64((install.timeIntervalSince1970 * 1000).rounded(.down))
        let elapsed = max(0, Int64((now().timeIntervalSince1970 * 1000).rounded(.down)) - installMillis)
        switch unit {
        case "hours": return String(elapsed / 3_600_000)
        case "minutes": return String(elapsed / 60_000)
        case "millis", "install_timestamp": return String(installMillis)
        default: return String(elapsed / 86_400_000)
        }
    }

    /// Creation date of the app's Documents folder's parent (the app container). It is kept
    /// across app updates and reset when the app is deleted and reinstalled.
    static func appContainerCreationDate() -> Date? {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let container = documents.deletingLastPathComponent()
        let attributes = try? fileManager.attributesOfItem(atPath: container.path)
        return attributes?[.creationDate] as? Date
    }
}
