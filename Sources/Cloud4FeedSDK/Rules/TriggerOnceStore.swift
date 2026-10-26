import Foundation

/// Persistent "trigger once" memory (Android: `survey_sdk_trigger_once`).
///
/// Remembered per survey and per user identity (the parameters given to `initialize`), so a
/// `triggerOnce` survey is shown once per user. Without user parameters it is once per device.
final class TriggerOnceStore {
    private let store: KeyValueStore

    init(store: KeyValueStore) {
        self.store = store
    }

    func hasShown(surveyId: String, userParameters: [String: String]) -> Bool {
        guard !surveyId.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return store.bool(forKey: Self.key(surveyId: surveyId, userParameters: userParameters))
    }

    func markShown(surveyId: String, userParameters: [String: String]) {
        guard !surveyId.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.set(true, forKey: Self.key(surveyId: surveyId, userParameters: userParameters))
        SDKLog.debug("triggerOnce survey \(surveyId) remembered for this user", .rules)
    }

    /// Forgets every remembered survey (all users on this device).
    func clear() {
        store.removeAll()
    }

    static func key(surveyId: String, userParameters: [String: String]) -> String {
        "\(surveyId)|\(StableHash.parameters(userParameters))"
    }
}
