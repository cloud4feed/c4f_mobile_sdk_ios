import Foundation

/// Session metrics and `setSessionData` values (Android: `ExclusionRuleEvaluator` session part +
/// `AppUsageUtils.getEnhancedSessionData`).
///
/// A session is one app process: `trackSessionStart` counts only its first call per process.
/// Counters are persisted, `setSessionData` values live in memory only.
final class SessionTracker {
    private enum Keys {
        static let sessionCount = "session_count"
        static let screenViewCount = "screen_view_count"
        static let sessionStart = "session_start_time"
        static let previousSession = "previous_session_time"
        static let lastSession = "last_session_time"
    }

    private let store: KeyValueStore
    private let now: () -> Date
    private var sessionTrackedInProcess = false
    private(set) var sessionData: [String: String] = [:]

    /// Name of the screen the SDK tracked last. Survives config reloads (Android v2.0.17 lesson).
    var currentScreen: String?

    init(store: KeyValueStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    // MARK: Tracking

    func trackSessionStart() {
        guard !sessionTrackedInProcess else { return }
        sessionTrackedInProcess = true

        let nowMillis = millis(now())
        let count = store.int(forKey: Keys.sessionCount) + 1
        let previousStart = store.double(forKey: Keys.sessionStart)
        store.set(count, forKey: Keys.sessionCount)
        store.set(previousStart, forKey: Keys.previousSession)
        store.set(nowMillis, forKey: Keys.sessionStart)
        store.set(nowMillis, forKey: Keys.lastSession)
        SDKLog.debug("Session tracked: #\(count)")
    }

    func trackScreenView() {
        let views = store.int(forKey: Keys.screenViewCount) + 1
        store.set(views, forKey: Keys.screenViewCount)
        SDKLog.debug("Screen view tracked: #\(views)")
    }

    func setSessionData(_ value: String, forKey key: String) {
        sessionData[key] = value
        SDKLog.debug("Session data set: \(key) = \(value)")
    }

    func clearSessionData() {
        sessionData.removeAll()
    }

    /// Clears counters and session values (e.g. for tests or a signed-out user).
    func reset() {
        store.removeAll()
        sessionData.removeAll()
        sessionTrackedInProcess = false
    }

    // MARK: Values

    var sessionCount: Int { store.int(forKey: Keys.sessionCount) }
    var screenViewCount: Int { store.int(forKey: Keys.screenViewCount) }

    /// SESSION source: `setSessionData` values win, then the automatic metrics.
    func sessionValue(forKey key: String) -> String? {
        sessionData[key] ?? automaticValue(forKey: key)
    }

    func automaticValue(forKey key: String) -> String? {
        switch key {
        case "session_count":
            return String(sessionCount)
        case "screen_view_count", "screens_count":
            return String(screenViewCount)
        case "session_duration_minutes":
            return sessionDurationMillis().map { String($0 / 60_000) }
        case "session_duration":
            // Seconds, same key as the Configuration Manager.
            return sessionDurationMillis().map { String($0 / 1_000) }
        case "first_launch":
            return sessionCount <= 1 ? "true" : "false"
        case "current_screen", "currentScreen":
            return currentScreen
        default:
            return nil
        }
    }

    /// APP_USAGE source.
    func appUsageValue(_ metric: String) -> String? {
        switch metric {
        case "sessions":
            return String(sessionCount)
        case "screen_views":
            return String(screenViewCount)
        case "last_session":
            // Minutes since the previous session started; no value on the very first session.
            let previous = store.double(forKey: Keys.previousSession)
            guard previous > 0 else { return nil }
            return String(max(0, Int64(millis(now()) - previous)) / 60_000)
        default:
            // "app_usage_time" is not measured (Android returns an empty value too).
            return nil
        }
    }

    private func sessionDurationMillis() -> Int64? {
        let start = store.double(forKey: Keys.sessionStart)
        guard start > 0 else { return nil }
        return max(0, Int64(millis(now()) - start))
    }

    private func millis(_ date: Date) -> Double {
        (date.timeIntervalSince1970 * 1000).rounded()
    }
}
