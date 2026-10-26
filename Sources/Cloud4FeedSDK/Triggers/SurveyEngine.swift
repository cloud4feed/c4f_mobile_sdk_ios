import Foundation

/// Platform-independent trigger decisions: "this event happened, which survey(s) should open?".
///
/// The UIKit layer (Phase 2) observes screens, buttons, scroll views, tabs and the app lifecycle,
/// feeds the events in here, handles timing (debounce, `timeDelay`) and presents the result.
/// Matching rules are the Android ones (`MobileSDK.kt`), including the v2.0.17 / v2.0.18 fixes:
/// the current screen survives config reloads, and scroll always respects `triggerScreens`.
final class SurveyEngine {
    private(set) var config: Config = .empty
    private(set) var isConfigLoaded = false

    let eligibility: Eligibility
    let session: SessionTracker
    let collector: SurveyDataCollector

    init(eligibility: Eligibility, session: SessionTracker, collector: SurveyDataCollector) {
        self.eligibility = eligibility
        self.session = session
        self.collector = collector
    }

    /// Applies a new configuration. Per-session display counters restart (as on Android);
    /// the current screen is kept.
    func apply(_ config: Config) {
        self.config = config
        isConfigLoaded = true
        eligibility.resetSessionCounters()
        SDKLog.info("Configuration applied: \(config.surveys.count) surveys")
    }

    // MARK: - Screen tracking

    /// Records a screen view and returns the navigation surveys to open for it.
    /// Screens whose name contains "survey" are ignored (the SDK's own screens).
    func screenDidAppear(_ screenName: String) -> [SurveyConfig] {
        guard !screenName.c4fContainsIgnoringCase("survey") else { return [] }
        session.currentScreen = screenName
        session.trackScreenView()
        return navigationSurveys(for: screenName)
    }

    func navigationSurveys(for screenName: String) -> [SurveyConfig] {
        config.surveys.filter { survey in
            survey.enableNavigationTrigger
                && Self.screenMatches(screenName, survey.triggerScreens, bidirectional: true)
                && eligibility.canShow(survey)
        }
    }

    /// Exit trigger: surveys whose `triggerScreens` contain the screen the user just left.
    /// An exit survey without trigger screens never fires (same as Android).
    func exitSurveys(leaving previousScreen: String, to newScreen: String?) -> [SurveyConfig] {
        if previousScreen.c4fContainsIgnoringCase("survey") { return [] }
        if let newScreen = newScreen, newScreen.c4fContainsIgnoringCase("survey") { return [] }
        return config.surveys.filter { survey in
            survey.enableExitTrigger
                && !survey.triggerScreens.isEmpty
                && survey.triggerScreens.contains { previousScreen.c4fContainsIgnoringCase($0) }
                && eligibility.canShow(survey)
        }
    }

    // MARK: - Button

    /// 1. A survey whose `buttonTriggerId` equals the id (highest priority wins).
    /// 2. Otherwise, for a predefined id (`survey_button`, ...), the generic button survey.
    func buttonSurvey(for buttonId: String) -> SurveyConfig? {
        let specific = config.surveys.filter { $0.enableButtonTrigger && $0.buttonTriggerId == buttonId }
        if let survey = Self.highestPriority(specific) {
            return eligibility.canShow(survey) ? survey : nil
        }
        guard SDKConstants.predefinedButtonIds.contains(buttonId) else {
            SDKLog.debug("No button survey for id '\(buttonId)'")
            return nil
        }
        let generic = config.surveys.filter { $0.enableButtonTrigger && ($0.buttonTriggerId ?? "").isEmpty }
        if let survey = Self.highestPriority(generic) {
            return eligibility.canShow(survey) ? survey : nil
        }
        return nil
    }

    /// Ids the UIKit button detector should watch.
    var watchedButtonIds: Set<String> {
        var ids = Set(config.surveys.compactMap { $0.enableButtonTrigger ? $0.buttonTriggerId : nil })
        if config.surveys.contains(where: { $0.enableButtonTrigger && ($0.buttonTriggerId ?? "").isEmpty }) {
            ids.formUnion(SDKConstants.predefinedButtonIds)
        }
        return ids
    }

    // MARK: - Tab

    /// Exact match after lowercasing and trimming; `tab_<name>` also matches `<name>`.
    /// The tab becomes the current screen context.
    func tabSurvey(for tabName: String) -> SurveyConfig? {
        let normalized = tabName.lowercased().trimmingCharacters(in: .whitespaces)
        session.currentScreen = normalized
        let matching = config.surveys.filter { survey in
            survey.enableTabChangeTrigger
                && survey.triggerTabs.contains { tab in
                    let configTab = tab.lowercased().trimmingCharacters(in: .whitespaces)
                    return normalized == configTab || normalized == "tab_\(configTab)"
                }
                && eligibility.canShow(survey)
        }
        return Self.highestPriority(matching)
    }

    // MARK: - Scroll

    /// `offsetPixels >= scrollThreshold` on a screen allowed by `triggerScreens`
    /// (empty = every screen). `screenName` defaults to the current screen.
    func scrollSurvey(offsetPixels: Int, screenName: String? = nil) -> SurveyConfig? {
        let screen = screenName ?? session.currentScreen ?? ""
        let matching = config.surveys.filter { survey in
            survey.enableScrollTrigger
                && offsetPixels >= survey.scrollThreshold
                && Self.screenMatches(screen, survey.triggerScreens, bidirectional: false)
                && eligibility.canShow(survey)
        }
        return Self.highestPriority(matching)
    }

    /// Smallest threshold of the scroll surveys; offsets below it cannot match anything.
    var minimumScrollThreshold: Int? {
        config.surveys.filter(\.enableScrollTrigger).map(\.scrollThreshold).min()
    }

    /// Whether the scroll observer is needed at all (Android only observes thresholds > 0).
    var hasScrollSurveys: Bool {
        config.surveys.contains { $0.enableScrollTrigger && $0.scrollThreshold > 0 }
    }

    // MARK: - App launch

    func appLaunchSurveys() -> [SurveyConfig] {
        config.surveys.filter { $0.enableAppLaunchTrigger && eligibility.canShow($0) }
    }

    // MARK: - App exit ("welcome back")

    /// Exit surveys without trigger screens are app-exit surveys: remembered when the app goes to
    /// the background and shown when the user comes back (Android `handleAppExit`).
    var appExitSurveyIds: [String] {
        config.surveys.filter { $0.enableExitTrigger && $0.triggerScreens.isEmpty }.map(\.surveyId)
    }

    func welcomeBackSurveys(ids: [String]) -> [SurveyConfig] {
        ids.compactMap { id in config.surveys.first { $0.surveyId == id } }
            .filter { $0.enableExitTrigger && $0.triggerScreens.isEmpty && eligibility.canShow($0) }
    }

    // MARK: - Identifiers from touches (React Native / hybrid)

    /// Configured button id matching `identifier` case-insensitively (React Native reports
    /// accessibility labels in lower case, as on Android).
    func buttonId(matching identifier: String) -> String? {
        let lowered = identifier.lowercased()
        return watchedButtonIds.first { $0.lowercased() == lowered }
    }

    /// Whether `name` is one of the configured tab names (same rule as `tabSurvey`).
    func isConfiguredTab(_ name: String) -> Bool {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        return config.surveys.contains { survey in
            survey.enableTabChangeTrigger && survey.triggerTabs.contains { tab in
                let configTab = tab.lowercased().trimmingCharacters(in: .whitespaces)
                return normalized == configTab || normalized == "tab_\(configTab)"
            }
        }
    }

    // MARK: - Manual display

    var surveyIds: [String] { config.surveys.map(\.surveyId) }

    func survey(withId id: String) -> SurveyConfig? {
        config.surveys.first { $0.surveyId == id }
    }

    /// Highest-priority survey that may be shown now, whatever its triggers (Android `showSurvey`).
    func anyEligibleSurvey() -> SurveyConfig? {
        Self.highestPriority(config.surveys.filter { eligibility.canShow($0) })
    }

    // MARK: - Display

    /// `triggerType == "delayed"` with a positive `timeDelay` waits that many milliseconds.
    static func delay(for survey: SurveyConfig) -> TimeInterval {
        survey.triggerType == "delayed" && survey.timeDelay > 0 ? Double(survey.timeDelay) / 1000 : 0
    }

    func surveyURL(for survey: SurveyConfig) -> String {
        collector.surveyURL(for: survey)
    }

    func recordShown(_ survey: SurveyConfig) {
        eligibility.recordShown(survey)
    }

    // MARK: - Helpers

    /// Empty `triggerScreens` = every screen. Otherwise case-insensitive "contains";
    /// navigation also accepts the reverse direction (config name contains the screen name).
    static func screenMatches(_ screen: String, _ triggerScreens: Set<String>, bidirectional: Bool) -> Bool {
        if triggerScreens.isEmpty { return true }
        return triggerScreens.contains { trigger in
            screen.c4fContainsIgnoringCase(trigger)
                || (bidirectional && !screen.isEmpty && trigger.c4fContainsIgnoringCase(screen))
        }
    }

    /// Highest `priority`; on a tie the first one in configuration order (same as Android).
    static func highestPriority(_ surveys: [SurveyConfig]) -> SurveyConfig? {
        surveys.max { $0.priority < $1.priority }
    }
}
