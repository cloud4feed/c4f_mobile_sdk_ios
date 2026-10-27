import Foundation

/// Automatic event detection for one UI platform (UIKit: `UIKitIntegration`).
protocol PlatformIntegration: AnyObject {
    /// Starts lifecycle observation; unless `hybridMode`, also screen / button / tab / scroll detection.
    func start(hybridMode: Bool, automaticScreenTracking: Bool)
    /// A new configuration was applied: re-scan the visible screen.
    func configurationApplied()
    /// The app reported a screen itself (`trackScreen`): scan the visible screen for buttons / scroll views.
    func screenTrackedManually()
    func stop()
}

/// Cloud4Feed survey SDK.
///
/// ```swift
/// // AppDelegate / App init
/// MobileSDK.initialize(apiKey: "sk_...", parameters: ["customerId": "1011"]).autoSetup()
///
/// // optional, wherever it applies
/// MobileSDK.shared?.trackScreen("home")
/// MobileSDK.shared?.setUserProperty("gold", forKey: "user_tier")
/// ```
///
/// Call the API from the main thread; calls from other threads are moved to the main thread.
public final class MobileSDK {

    // MARK: - Instance management

    /// The SDK set up by `initialize`. Nil before the first `initialize`.
    public private(set) static var shared: MobileSDK?

    public static var sdkVersion: String { SDKConstants.sdkVersion }

    /// Turns SDK logging (`os.Logger`, subsystem `com.cloud4feed.mobilesdk`) on or off.
    public static var isLoggingEnabled: Bool {
        get { SDKLog.isEnabled }
        set { SDKLog.isEnabled = newValue }
    }

    /// Sets up the SDK and starts loading the configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Configuration Manager API key.
    ///   - parameters: user parameters sent with the configuration request
    ///     (e.g. `["customerId": "1011"]` for transactional surveys).
    ///   - lookupKeys: keys whose values are read from storage (`setUserProperty` values,
    ///     then `UserDefaults.standard`). Missing keys are skipped. `parameters` win on conflicts.
    ///
    /// Calling it again with the same API key only updates the parameters (the configuration is
    /// reloaded when they changed). A different API key replaces the SDK instance.
    @discardableResult
    public static func initialize(apiKey: String,
                                  parameters: [String: String] = [:],
                                  lookupKeys: [String] = []) -> MobileSDK {
        if let existing = shared, existing.apiKey == apiKey {
            existing.updateParameters(existing.resolve(parameters: parameters, lookupKeys: lookupKeys))
            return existing
        }
        shared?.shutdown()

        let sdk = MobileSDK(core: SDKCore(apiKey: apiKey, device: makeDefaultDeviceInfo()),
                            presenter: makeDefaultPresenter(),
                            scheduler: MainQueueScheduler(),
                            dispatchToMain: performOnMain,
                            integrationFactory: makeDefaultIntegration)
        sdk.core.updateParameters(sdk.resolve(parameters: parameters, lookupKeys: lookupKeys))
        activate(sdk)
        SDKLog.info("SDK \(SDKConstants.sdkVersion) initialized with \(sdk.core.parameters.count) parameters")
        sdk.reloadConfiguration()
        return sdk
    }

    /// Deep link that arrived before `initialize` (an app opened from a link while it was not
    /// running gets the link before its startup code runs). Applied by the next `initialize`.
    static var pendingURL: URL?

    /// Deep links: query parameters become the URL value source. Safe to call at any time:
    /// before `initialize` the link is kept and applied when the SDK starts. Prefer this over
    /// `MobileSDK.shared?.handle(url:)`, which drops a link that arrives before `initialize`.
    public static func handle(url: URL) {
        performOnMain {
            if let sdk = shared {
                sdk.handle(url: url)
            } else {
                pendingURL = url
                SDKLog.debug("Deep link kept until initialize")
            }
        }
    }

    /// Makes `sdk` the shared instance and applies a deep link that arrived before it existed.
    private static func activate(_ sdk: MobileSDK) {
        shared = sdk
        if let url = pendingURL {
            pendingURL = nil
            sdk.core.urlParameters.update(from: url)
            SDKLog.debug("Deep link received before initialize applied")
        }
    }

    // MARK: - State

    public let apiKey: String
    let core: SDKCore
    let coordinator: TriggerCoordinator
    private let dispatchToMain: (@escaping () -> Void) -> Void
    private let integrationFactory: (TriggerCoordinator, SurveyEngine) -> PlatformIntegration?
    private var integration: PlatformIntegration?
    private var loadTask: Task<Void, Never>?
    private var isSetUp = false

    public private(set) var isHybridMode = false
    /// Automatic screen tracking for UIKit view controllers (on by default). Set before `autoSetup`.
    public private(set) var isAutomaticScreenTrackingEnabled = true

    /// Called on the main thread after every configuration load; `true` when surveys were received.
    public var onConfigurationLoaded: ((Bool) -> Void)?

    /// Called on the main thread with the survey id.
    public var onSurveyShown: ((String) -> Void)? {
        get { coordinator.onSurveyShown }
        set { coordinator.onSurveyShown = newValue }
    }

    /// Called on the main thread with the survey id when the user closes a survey.
    public var onSurveyClosed: ((String) -> Void)? {
        get { coordinator.onSurveyClosed }
        set { coordinator.onSurveyClosed = newValue }
    }

    init(core: SDKCore,
         presenter: SurveyPresenting,
         scheduler: Scheduling,
         dispatchToMain: @escaping (@escaping () -> Void) -> Void,
         integrationFactory: @escaping (TriggerCoordinator, SurveyEngine) -> PlatformIntegration?,
         now: @escaping () -> Date = Date.init) {
        self.apiKey = core.apiKey
        self.core = core
        self.coordinator = TriggerCoordinator(core: core, presenter: presenter, scheduler: scheduler, now: now)
        self.dispatchToMain = dispatchToMain
        self.integrationFactory = integrationFactory
    }

    // MARK: - Setup

    /// Starts automatic detection: screens (UIKit view controllers), buttons, tabs, scroll views,
    /// app launch and app exit. Call once, e.g. right after `initialize`.
    @discardableResult
    public func autoSetup() -> MobileSDK {
        dispatchToMain { [self] in
            guard !isSetUp else { return }
            isSetUp = true
            core.session.trackSessionStart()
            integration = integrationFactory(coordinator, core.engine)
            integration?.start(hybridMode: isHybridMode, automaticScreenTracking: isAutomaticScreenTrackingEnabled)
            coordinator.appDidLaunch()
            SDKLog.info("autoSetup done (hybrid: \(isHybridMode), auto screens: \(isAutomaticScreenTrackingEnabled))")
        }
        return self
    }

    /// For React Native / Flutter: no screen swizzle and no UIKit control scanning; screens come
    /// from `trackScreen`. Scroll views in the window are still observed, and taps are matched by
    /// accessibility label / identifier (React Native `accessibilityLabel` / `testID`), like the
    /// Android bridge. Call before `autoSetup`.
    @discardableResult
    public func enableHybridMode() -> MobileSDK {
        isHybridMode = true
        return self
    }

    /// Turns off automatic UIKit screen tracking; report screens with `trackScreen`. Call before `autoSetup`.
    @discardableResult
    public func disableAutomaticScreenTracking() -> MobileSDK {
        isAutomaticScreenTrackingEnabled = false
        return self
    }

    // MARK: - Events

    /// The user is on `screenName` (navigation + exit triggers). Names must match the
    /// Configuration Manager's trigger screens; matching is case-insensitive "contains".
    public func trackScreen(_ screenName: String) {
        dispatchToMain { [self] in
            coordinator.trackScreen(screenName)
            integration?.screenTrackedManually()
        }
    }

    /// The user selected the tab `tabName` (tab change trigger, exact match; `tab_<name>` also matches).
    public func trackTab(_ tabName: String) {
        dispatchToMain { [self] in coordinator.trackTab(tabName) }
    }

    /// A button with this id was tapped (button trigger).
    public func triggerButton(_ buttonId: String) {
        dispatchToMain { [self] in coordinator.triggerButton(buttonId) }
    }

    /// The current screen is scrolled `offsetPixels` pixels from the top (scroll trigger).
    public func triggerScroll(offsetPixels: Int) {
        dispatchToMain { [self] in coordinator.scrollChanged(offsetPixels: offsetPixels) }
    }

    /// Shows the highest-priority survey that may be shown now.
    public func showSurvey() {
        dispatchToMain { [self] in coordinator.showAnySurvey() }
    }

    /// Shows the survey with this id if its display rules allow it.
    public func showSurvey(id: String) {
        dispatchToMain { [self] in coordinator.showSurvey(id: id) }
    }

    /// Deep links: query parameters become the URL value source. See also the static
    /// `MobileSDK.handle(url:)`, which also works before `initialize`.
    public func handle(url: URL) {
        dispatchToMain { [self] in core.urlParameters.update(from: url) }
    }

    // MARK: - Data

    /// Stores a STORAGE value (custom parameters / exclusion rules read it by key). Nil removes it.
    public func setUserProperty(_ value: String?, forKey key: String) {
        dispatchToMain { [self] in core.setUserProperty(value, forKey: key) }
    }

    /// Sets a SESSION value for this app session (kept in memory).
    public func setSessionData(_ value: String, forKey key: String) {
        dispatchToMain { [self] in core.setSessionData(value, forKey: key) }
    }

    /// Clears session values and counters (session count, screen views).
    public func resetSessionData() {
        dispatchToMain { [self] in
            core.session.reset()
            coordinator.resetScreenState()
        }
    }

    /// Also read STORAGE values from this UserDefaults suite (e.g. an app group).
    public func addStorageSuite(named suiteName: String) {
        dispatchToMain { [self] in core.storage.addStore(UserDefaultsStore(suiteName: suiteName)) }
    }

    /// Forgets which "trigger once" surveys were shown (all users on this device).
    public func clearTriggerOnceHistory() {
        dispatchToMain { [self] in core.eligibility.clearTriggerOnceHistory() }
    }

    // MARK: - Configuration

    public var currentParameters: [String: String] { core.parameters }

    public var isConfigurationLoaded: Bool { core.engine.isConfigLoaded }

    /// Configuration loaded and it contains at least one survey.
    public var isReady: Bool { core.engine.isConfigLoaded && !core.engine.config.surveys.isEmpty }

    /// Replaces the user parameters and reloads the configuration when they changed.
    public func updateParameters(_ parameters: [String: String]) {
        dispatchToMain { [self] in
            guard parameters != core.parameters else {
                SDKLog.debug("Parameters unchanged")
                return
            }
            core.updateParameters(parameters)
            coordinator.clearQueue()
            reloadConfiguration()
        }
    }

    /// Fetches the configuration from the network, ignoring the cache.
    public func refreshConfiguration(completion: ((Bool) -> Void)? = nil) {
        dispatchToMain { [self] in reloadConfiguration(forceRefresh: true, completion: completion) }
    }

    func reloadConfiguration(forceRefresh: Bool = false, completion: ((Bool) -> Void)? = nil) {
        loadTask?.cancel()
        let core = self.core
        let parameters = core.parameters
        loadTask = Task { [weak self] in
            let (config, source) = await core.resolveConfiguration(parameters: parameters, forceRefresh: forceRefresh)
            guard !Task.isCancelled else { return }
            self?.dispatchToMain {
                self?.apply(config, source: source, completion: completion)
            }
        }
    }

    private func apply(_ config: Config?, source: ConfigSource, completion: ((Bool) -> Void)?) {
        if let config = config {
            core.engine.apply(config)
        } else if !core.engine.isConfigLoaded {
            // No cache and no network: continue with an empty configuration so waiting events stop.
            core.engine.apply(.empty)
        }
        SDKLog.info("Configuration source: \(source.rawValue), surveys: \(core.engine.config.surveys.count)")
        coordinator.configurationApplied()
        integration?.configurationApplied()
        let hasSurveys = config.map { !$0.surveys.isEmpty } ?? false
        onConfigurationLoaded?(hasSurveys)
        completion?(hasSurveys)
    }

    // MARK: - Bridge support (React Native / Flutter)

    /// Accessibility labels / identifiers under a tap. Used by hybrid frameworks whose buttons
    /// are not UIKit controls; matches configured button ids and tab names.
    public func handleTouchIdentifiers(_ identifiers: [String]) {
        dispatchToMain { [self] in coordinator.touchIdentifiers(identifiers) }
    }

    public var surveyIds: [String] { core.engine.surveyIds }

    /// Whether the exclusion rules of this survey exclude the current user.
    public func isUserExcluded(surveyId: String) -> Bool {
        guard let survey = core.engine.survey(withId: surveyId) else { return false }
        return core.eligibility.isExcluded(survey)
    }

    public var isShowingSurvey: Bool { coordinator.isShowingSurvey }

    public var queueStatus: String { coordinator.queueStatus }

    public func clearSurveyQueue() {
        dispatchToMain { [self] in coordinator.clearQueue() }
    }

    /// Restarts the per-session display counters and screen state (Android `resetTriggers`).
    public func resetTriggers() {
        dispatchToMain { [self] in coordinator.resetTriggers() }
    }

    /// Multi-line status text (Android `debugSurveyStatus`).
    public func debugStatusText() -> String {
        var lines = ["=== MULTI-SURVEY STATUS ==="]
        lines += debugStatus().sorted { $0.key < $1.key }.map { "• \($0.key): \($0.value)" }
        for survey in core.engine.config.surveys {
            let decision = core.eligibility.decision(for: survey)
            let state: String
            if case .blocked(let reason) = decision { state = "blocked (\(reason.rawValue))" } else { state = "can show" }
            lines.append("• Survey \(survey.surveyId): \(state), priority \(survey.priority)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Debug

    /// Snapshot for debugging / bridges (`getDebugStatus`).
    public func debugStatus() -> [String: String] {
        let engine = core.engine
        return [
            "sdkVersion": SDKConstants.sdkVersion,
            "platform": "iOS",
            "configurationLoaded": String(engine.isConfigLoaded),
            "surveyCount": String(engine.config.surveys.count),
            "surveyIds": engine.config.surveys.map(\.surveyId).joined(separator: ","),
            "currentScreen": core.session.currentScreen ?? "",
            "parameterCount": String(core.parameters.count),
            "hybridMode": String(isHybridMode),
            "automaticScreenTracking": String(isAutomaticScreenTrackingEnabled),
            "isShowingSurvey": String(coordinator.isShowingSurvey),
            "queuedSurveys": String(coordinator.queue.count),
            "sessionCount": String(core.session.sessionCount),
        ]
    }

    // MARK: - Teardown

    /// Stops observers and pending work. `initialize` with another API key calls this.
    public func shutdown() {
        dispatchToMain { [self] in
            loadTask?.cancel()
            integration?.stop()
            integration = nil
            coordinator.clearQueue()
            if MobileSDK.shared === self { MobileSDK.shared = nil }
        }
    }

    // MARK: - Helpers

    private func resolve(parameters: [String: String], lookupKeys: [String]) -> [String: String] {
        core.lookUpParameters(lookupKeys).merging(parameters) { _, direct in direct }
    }

    /// Test hook: install an instance as `shared` the way `initialize` does (nil clears it).
    static func setShared(_ sdk: MobileSDK?) {
        if let sdk = sdk {
            activate(sdk)
        } else {
            shared = nil
        }
    }
}

// MARK: - Platform defaults

extension MobileSDK {
    static func makeDefaultPresenter() -> SurveyPresenting {
        #if canImport(UIKit) && canImport(WebKit) && !os(watchOS)
        return UIKitSurveyPresenter()
        #else
        return NoUIPresenter()
        #endif
    }

    static func makeDefaultDeviceInfo() -> DeviceInfoProviding {
        #if canImport(UIKit) && !os(watchOS)
        return UIKitDeviceInfo()
        #else
        return FoundationDeviceInfo()
        #endif
    }

    static func makeDefaultIntegration(coordinator: TriggerCoordinator, engine: SurveyEngine) -> PlatformIntegration? {
        #if canImport(UIKit) && !os(watchOS)
        return UIKitIntegration(coordinator: coordinator, engine: engine)
        #else
        return nil
        #endif
    }
}
