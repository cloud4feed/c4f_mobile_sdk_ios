import Foundation

/// Turns app events into survey displays: timing, debounce, delays, the display queue and the
/// app-exit ("welcome back") flow. Platform-independent; the UIKit layer and the bridges feed it.
/// Main thread only.
///
/// Timings follow the Android SDK (`MobileSDK.kt`):
/// - after a survey closes, screen and tab events are ignored for 2 s (the screen under the
///   survey re-appears and must not trigger again)
/// - tab events are debounced for 1 s, `triggerButton` calls for 0.5 s
/// - a queued survey opens 0.5 s after the previous one closed
/// - events that arrive before the configuration is loaded are replayed once it is
final class TriggerCoordinator {
    struct Timing {
        var postSurveyCooldown: TimeInterval = 2.0
        var tabDebounce: TimeInterval = 1.0
        var buttonDebounce: TimeInterval = 0.5
        var scrollCooldown: TimeInterval = 3.0
        var scrollThrottle: TimeInterval = 0.2
        var queueDelay: TimeInterval = 0.5
        var buttonRetryInterval: TimeInterval = 1.0
        var maxButtonRetries = 10
        var welcomeBackDelay: TimeInterval = 1.5
    }

    private enum ExitKeys {
        static let pending = "pending_surveys"
    }

    private let core: SDKCore
    private var engine: SurveyEngine { core.engine }
    private let scheduler: Scheduling
    private let now: () -> Date
    var presenter: SurveyPresenting
    var timing = Timing()

    /// Called with the survey id when a survey is shown / closed.
    var onSurveyShown: ((String) -> Void)?
    var onSurveyClosed: ((String) -> Void)?

    // Screen state
    private(set) var previousScreen: String?
    private var pendingScreen: String?
    private var pendingTab: String?
    private var delayedScreenSurveys: [Cancellable] = []
    private var scrollFiredOnScreen: Set<String> = []

    // Debounce state
    private var lastTabEvent: Date?
    private var lastButtonEvent: Date?
    private var lastScrollFire: Date?
    private var lastScrollEvaluation: Date?
    private var throttledScrollOffset: Int?
    /// "Scroll reached a threshold but nothing matched" is logged once per screen visit.
    private var scrollNoMatchLogged = false
    private var scrollEventLogged = false
    private var isTrailingScrollScheduled = false
    private var lastSurveyClosed: Date?

    // App launch / exit
    private var appLaunchRequested = false
    private var appLaunchHandled = false
    private var welcomeBackRequested = false

    // Display queue
    private(set) var isShowingSurvey = false
    private(set) var currentSurveyId: String?
    private(set) var queue: [SurveyConfig] = []

    init(core: SDKCore,
         presenter: SurveyPresenting,
         scheduler: Scheduling = MainQueueScheduler(),
         now: @escaping () -> Date = Date.init) {
        self.core = core
        self.presenter = presenter
        self.scheduler = scheduler
        self.now = now
    }

    // MARK: - Configuration

    /// Call after a configuration was applied to the engine. Replays what happened before.
    func configurationApplied() {
        if let screen = pendingScreen {
            pendingScreen = nil
            trackScreen(screen)
        }
        if let tab = pendingTab {
            pendingTab = nil
            trackTab(tab)
        }
        if appLaunchRequested && !appLaunchHandled {
            runAppLaunch()
        }
        if welcomeBackRequested {
            welcomeBackRequested = false
            showWelcomeBackSurveys()
        }
    }

    // MARK: - Screens (navigation + exit)

    /// The user is now on `rawName`. Fires exit surveys of the previous screen and navigation
    /// surveys of the new one, highest priority first (exit first on a tie).
    func trackScreen(_ rawName: String) {
        let name = Self.normalize(rawName)
        guard !name.isEmpty else { return }
        // The SDK's own survey screens never count as app screens.
        guard !name.c4fContainsIgnoringCase("survey") else { return }

        // Context first, so buttons / scroll / SESSION current_screen know the screen at once.
        core.session.currentScreen = name

        guard engine.isConfigLoaded else {
            pendingScreen = name
            SDKLog.debug("Config not loaded yet, screen '\(name)' will be evaluated later")
            return
        }
        guard !isInPostSurveyCooldown else { return }
        guard name != previousScreen else { return }

        let oldScreen = previousScreen
        previousScreen = name
        core.session.trackScreenView()
        scrollFiredOnScreen.removeAll()
        scrollNoMatchLogged = false
        scrollEventLogged = false
        delayedScreenSurveys.forEach { $0.cancel() }
        delayedScreenSurveys.removeAll()
        SDKLog.debug("Screen transition: \(oldScreen ?? "-") -> \(name)")

        var candidates: [(survey: SurveyConfig, isExit: Bool)] = []
        if let oldScreen = oldScreen {
            candidates += engine.exitSurveys(leaving: oldScreen, to: name).map { (survey: $0, isExit: true) }
        }
        for survey in engine.navigationSurveys(for: name)
            where !candidates.contains(where: { $0.survey.surveyId == survey.surveyId }) {
            candidates.append((survey: survey, isExit: false))
        }

        let ordered = Self.stableSorted(candidates) { lhs, rhs in
            if lhs.survey.priority != rhs.survey.priority { return lhs.survey.priority > rhs.survey.priority }
            return lhs.isExit && !rhs.isExit
        }

        for candidate in ordered {
            let delay = candidate.isExit ? 0 : SurveyEngine.delay(for: candidate.survey)
            if delay > 0 {
                let survey = candidate.survey
                let item = scheduler.schedule(after: delay) { [weak self] in
                    guard let self = self, self.previousScreen == name,
                          self.engine.eligibility.canShow(survey) else { return }
                    self.show(survey)
                }
                delayedScreenSurveys.append(item)
            } else {
                show(candidate.survey)
            }
        }
    }

    // MARK: - Tabs

    func trackTab(_ rawName: String) {
        let name = Self.normalize(rawName)
        guard !name.isEmpty else { return }
        core.session.currentScreen = name

        guard engine.isConfigLoaded else {
            pendingTab = name
            return
        }
        guard !isInPostSurveyCooldown else { return }
        if let last = lastTabEvent, now().timeIntervalSince(last) < timing.tabDebounce {
            SDKLog.debug("Tab event debounced: \(name)")
            return
        }
        lastTabEvent = now()
        scrollFiredOnScreen.removeAll()

        guard let survey = engine.tabSurvey(for: name) else {
            SDKLog.debug("No tab survey for '\(name)'")
            return
        }
        showRespectingDelay(survey)
    }

    // MARK: - Buttons

    func triggerButton(_ buttonId: String) {
        triggerButton(buttonId, attempt: 0)
    }

    private func triggerButton(_ buttonId: String, attempt: Int) {
        guard engine.isConfigLoaded else {
            // The tap came while the configuration was loading: try again shortly (Android does the same).
            if attempt < timing.maxButtonRetries {
                scheduler.schedule(after: timing.buttonRetryInterval) { [weak self] in
                    self?.triggerButton(buttonId, attempt: attempt + 1)
                }
            }
            return
        }
        if attempt == 0, let last = lastButtonEvent, now().timeIntervalSince(last) < timing.buttonDebounce {
            SDKLog.debug("Button event debounced: \(buttonId)")
            return
        }
        lastButtonEvent = now()

        guard let survey = engine.buttonSurvey(for: buttonId) else { return }
        show(survey)
    }

    // MARK: - Touch identifiers (React Native)

    /// Accessibility labels / identifiers under a tap (React Native has no UIKit buttons).
    /// A configured tab name becomes a tab event, a configured button id a button event.
    /// Other labels are ignored, so tapping e.g. a product card does not change the screen context.
    func touchIdentifiers(_ identifiers: [String]) {
        guard engine.isConfigLoaded else { return }
        let normalized = identifiers.map(Self.normalize).filter { !$0.isEmpty }
        if let tab = normalized.first(where: { engine.isConfiguredTab($0) }) {
            trackTab(tab)
        }
        if let buttonId = normalized.lazy.compactMap({ self.engine.buttonId(matching: $0) }).first {
            triggerButton(buttonId)
        }
    }

    // MARK: - Scroll

    /// Scroll position of the current screen in pixels (0 = top). A scroll survey fires at most
    /// once per screen visit.
    func scrollChanged(offsetPixels: Int) {
        if !scrollEventLogged {
            scrollEventLogged = true
            SDKLog.debug("Scroll events received on '\(core.session.currentScreen ?? "-")' (first: \(offsetPixels)px)")
        }
        guard engine.isConfigLoaded, !isShowingSurvey,
              let minimum = engine.minimumScrollThreshold, offsetPixels >= minimum else { return }
        if let last = lastScrollFire, now().timeIntervalSince(last) < timing.scrollCooldown { return }
        // Scroll views report every frame; evaluating the rules a few times per second is enough.
        // The latest offset of a throttled burst is evaluated afterwards, so stopping right after
        // crossing the threshold still triggers.
        if let last = lastScrollEvaluation {
            let elapsed = now().timeIntervalSince(last)
            if elapsed < timing.scrollThrottle {
                throttledScrollOffset = offsetPixels
                if !isTrailingScrollScheduled {
                    isTrailingScrollScheduled = true
                    scheduler.schedule(after: timing.scrollThrottle - elapsed) { [weak self] in
                        guard let self = self else { return }
                        self.isTrailingScrollScheduled = false
                        if let offset = self.throttledScrollOffset {
                            self.throttledScrollOffset = nil
                            self.scrollChanged(offsetPixels: offset)
                        }
                    }
                }
                return
            }
        }
        lastScrollEvaluation = now()
        throttledScrollOffset = nil

        guard let survey = engine.scrollSurvey(offsetPixels: offsetPixels) else {
            if !scrollNoMatchLogged {
                scrollNoMatchLogged = true
                SDKLog.debug("Scroll \(offsetPixels)px on '\(core.session.currentScreen ?? "-")': no survey can be shown")
            }
            return
        }
        guard !scrollFiredOnScreen.contains(survey.surveyId) else { return }
        // Only a survey that was actually shown (or queued) uses up this screen visit;
        // if presenting failed, the next scroll event tries again.
        guard show(survey) else { return }
        scrollFiredOnScreen.insert(survey.surveyId)
        lastScrollFire = now()
    }

    // MARK: - App lifecycle

    /// Call once when the SDK is set up (process start).
    func appDidLaunch() {
        appLaunchRequested = true
        welcomeBackRequested = true // pending app-exit surveys of the last session (Android ON_START)
        if engine.isConfigLoaded {
            configurationApplied()
        }
    }

    private func runAppLaunch() {
        appLaunchHandled = true
        for survey in engine.appLaunchSurveys() {
            showRespectingDelay(survey)
        }
    }

    func appDidEnterBackground() {
        let ids = engine.appExitSurveyIds
        guard !ids.isEmpty else { return }
        var pending = core.exitStore.object(forKey: ExitKeys.pending) as? [String] ?? []
        for id in ids where !pending.contains(id) { pending.append(id) }
        core.exitStore.set(pending, forKey: ExitKeys.pending)
        SDKLog.debug("Saved \(ids.count) app-exit surveys for the next visit")
    }

    func appWillEnterForeground() {
        if engine.isConfigLoaded {
            showWelcomeBackSurveys()
        } else {
            welcomeBackRequested = true
        }
    }

    private func showWelcomeBackSurveys() {
        let ids = core.exitStore.object(forKey: ExitKeys.pending) as? [String] ?? []
        guard !ids.isEmpty else { return }
        core.exitStore.set(nil, forKey: ExitKeys.pending)
        scheduler.schedule(after: timing.welcomeBackDelay) { [weak self] in
            guard let self = self else { return }
            for survey in self.engine.welcomeBackSurveys(ids: ids) {
                SDKLog.debug("Showing welcome-back survey \(survey.surveyId)")
                self.show(survey)
            }
        }
    }

    // MARK: - Manual display

    @discardableResult
    func showSurvey(id: String) -> Bool {
        guard let survey = engine.survey(withId: id), engine.eligibility.canShow(survey) else {
            SDKLog.debug("Survey \(id) cannot be shown")
            return false
        }
        show(survey)
        return true
    }

    @discardableResult
    func showAnySurvey() -> Bool {
        guard let survey = engine.anyEligibleSurvey() else { return false }
        show(survey)
        return true
    }

    // MARK: - Display queue

    private func showRespectingDelay(_ survey: SurveyConfig) {
        let delay = SurveyEngine.delay(for: survey)
        guard delay > 0 else {
            show(survey)
            return
        }
        scheduler.schedule(after: delay) { [weak self] in
            guard let self = self, self.engine.eligibility.canShow(survey) else { return }
            self.show(survey)
        }
    }

    /// One survey at a time. Others wait in a priority-ordered queue without duplicates.
    /// Returns true when the survey was shown or queued.
    @discardableResult
    func show(_ survey: SurveyConfig) -> Bool {
        if isShowingSurvey {
            guard survey.surveyId != currentSurveyId,
                  !queue.contains(where: { $0.surveyId == survey.surveyId }) else { return false }
            let index = queue.firstIndex { $0.priority < survey.priority } ?? queue.endIndex
            queue.insert(survey, at: index)
            SDKLog.debug("Survey \(survey.surveyId) queued (\(queue.count) waiting)")
            return true
        }

        let url = engine.surveyURL(for: survey)
        let request = SurveyPresentationRequest(survey: survey, url: url)
        isShowingSurvey = true
        currentSurveyId = survey.surveyId

        let surveyId = survey.surveyId
        let presented = presenter.present(request) { [weak self] in
            self?.surveyClosed(surveyId)
        }
        guard presented else {
            isShowingSurvey = false
            currentSurveyId = nil
            processQueue()
            return false
        }
        engine.recordShown(survey)
        SDKLog.info("Survey shown: \(surveyId)")
        onSurveyShown?(surveyId)
        return true
    }

    private func surveyClosed(_ surveyId: String) {
        guard currentSurveyId == surveyId else { return }
        isShowingSurvey = false
        currentSurveyId = nil
        lastSurveyClosed = now()
        SDKLog.info("Survey closed: \(surveyId)")
        onSurveyClosed?(surveyId)
        processQueue()
    }

    private func processQueue() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        scheduler.schedule(after: timing.queueDelay) { [weak self] in
            guard let self = self else { return }
            if self.engine.eligibility.canShow(next) {
                self.show(next)
            } else {
                self.processQueue()
            }
        }
    }

    func clearQueue() {
        queue.removeAll()
    }

    /// Android `getQueueStatus` format.
    var queueStatus: String {
        queue.isEmpty
            ? "Queue: Empty"
            : "Queue: \(queue.count) surveys - " + queue.map { "(P:\($0.priority))" }.joined(separator: ", ")
    }

    /// Android `resetTriggers`: display counters, screen state and pending delayed surveys.
    func resetTriggers() {
        engine.eligibility.resetSessionCounters()
        resetScreenState()
        lastScrollFire = nil
        lastTabEvent = nil
        lastButtonEvent = nil
    }

    /// Forgets screen state (e.g. after `resetSessionData`).
    func resetScreenState() {
        previousScreen = nil
        pendingScreen = nil
        pendingTab = nil
        scrollFiredOnScreen.removeAll()
        delayedScreenSurveys.forEach { $0.cancel() }
        delayedScreenSurveys.removeAll()
    }

    // MARK: - Helpers

    private var isInPostSurveyCooldown: Bool {
        guard let closed = lastSurveyClosed else { return false }
        let inCooldown = now().timeIntervalSince(closed) < timing.postSurveyCooldown
        if inCooldown { SDKLog.debug("Event ignored: post-survey cooldown") }
        return inCooldown
    }

    static func normalize(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stableSorted<T>(_ items: [T], by areInOrder: (T, T) -> Bool) -> [T] {
        items.enumerated()
            .sorted { lhs, rhs in
                if areInOrder(lhs.element, rhs.element) { return true }
                if areInOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
