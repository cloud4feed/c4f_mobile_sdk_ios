import XCTest
@testable import Cloud4FeedSDK

final class MobileSDKTests: XCTestCase {
    private var env: TestEnvironment!
    private var presenter: FakePresenter!
    private var scheduler: ManualScheduler!
    private var integration: RecordingIntegration!

    private let response = """
    {"data": {"cacheDurationHours": 24, "surveys": [
      {"surveyId": "nav", "baseUrl": "https://cx.cloud4feed.com/?c=nav", "enableNavigationTrigger": true,
       "triggerScreens": ["notifications"],
       "customParams": [{"name": "param_1", "source": "STORAGE", "key": "customerId"},
                        {"name": "param_5", "source": "SESSION", "key": "current_screen"}]},
      {"surveyId": "btn", "baseUrl": "https://cx.cloud4feed.com/?c=btn", "enableButtonTrigger": true}
    ]}}
    """

    override func setUp() {
        SDKLog.isEnabled = false
        env = TestEnvironment()
        presenter = FakePresenter()
        scheduler = ManualScheduler(clock: env.clock)
        integration = RecordingIntegration()
    }

    override func tearDown() {
        MobileSDK.setShared(nil)
        MobileSDK.pendingURL = nil
        env.cleanUp()
    }

    private func makeSDK(transport: MockTransport, parameters: [String: String] = [:]) -> MobileSDK {
        let integration = self.integration!
        let sdk = MobileSDK(core: env.makeCore(parameters: parameters, transport: transport),
                            presenter: presenter,
                            scheduler: scheduler,
                            dispatchToMain: { $0() },
                            integrationFactory: { _, _ in integration },
                            now: env.clock.now)
        MobileSDK.setShared(sdk)
        return sdk
    }

    private func load(_ sdk: MobileSDK, forceRefresh: Bool = false) -> Bool {
        let loaded = expectation(description: "configuration loaded")
        var result = false
        sdk.onConfigurationLoaded = { hasSurveys in
            result = hasSurveys
            loaded.fulfill()
        }
        sdk.reloadConfiguration(forceRefresh: forceRefresh)
        wait(for: [loaded], timeout: 5)
        return result
    }

    func testEndToEndNavigationWithCustomParams() {
        let sdk = makeSDK(transport: MockTransport([.response(status: 200, body: response)]),
                          parameters: ["customerId": "1011"])
        sdk.autoSetup()
        XCTAssertEqual(integration.startedHybrid, false)
        XCTAssertEqual(integration.startedAutoScreens, true)

        sdk.setUserProperty("1011", forKey: "customerId")
        sdk.trackScreen("Home")
        XCTAssertTrue(load(sdk))
        XCTAssertTrue(sdk.isReady)
        XCTAssertEqual(integration.configurationAppliedCount, 1)

        sdk.trackScreen("Notifications")
        XCTAssertEqual(presenter.presented.first?.url,
                       "https://cx.cloud4feed.com/?c=nav&param_1=1011&param_5=notifications")
        XCTAssertEqual(integration.manualScreens, 2)
    }

    func testButtonBeforeConfigIsShownAfterLoad() {
        let sdk = makeSDK(transport: MockTransport([.response(status: 200, body: response)]))
        sdk.triggerButton("survey_button")
        XCTAssertTrue(load(sdk))
        scheduler.advance(seconds: 1)
        XCTAssertEqual(presenter.presentedIds, ["btn"])
    }

    func testCallbacks() {
        let sdk = makeSDK(transport: MockTransport([.response(status: 200, body: response)]))
        var shown: [String] = []
        var closed: [String] = []
        sdk.onSurveyShown = { shown.append($0) }
        sdk.onSurveyClosed = { closed.append($0) }
        XCTAssertTrue(load(sdk))
        sdk.showSurvey(id: "btn")
        presenter.closeCurrent()
        XCTAssertEqual(shown, ["btn"])
        XCTAssertEqual(closed, ["btn"])
    }

    func testNetworkFailureWithoutCacheGivesEmptyConfig() {
        let sdk = makeSDK(transport: MockTransport([.response(status: 401, body: "")]))
        XCTAssertFalse(load(sdk))
        XCTAssertTrue(sdk.isConfigurationLoaded, "waiting events stop waiting")
        XCTAssertFalse(sdk.isReady)
    }

    func testHybridModeAndScreenTrackingFlags() {
        let sdk = makeSDK(transport: MockTransport([]))
        sdk.enableHybridMode().disableAutomaticScreenTracking().autoSetup()
        sdk.autoSetup() // second call is ignored
        XCTAssertEqual(integration.startedHybrid, true)
        XCTAssertEqual(integration.startedAutoScreens, false)
        XCTAssertEqual(sdk.debugStatus()["hybridMode"], "true")
        XCTAssertEqual(sdk.debugStatus()["platform"], "iOS")
    }

    func testUpdateParametersReloadsOnlyOnChange() {
        let transport = MockTransport([.response(status: 200, body: response), .response(status: 200, body: response)])
        let sdk = makeSDK(transport: transport, parameters: ["customerId": "1011"])
        XCTAssertTrue(load(sdk))

        sdk.updateParameters(["customerId": "1011"])
        XCTAssertEqual(transport.requests.count, 1)

        let reloaded = expectation(description: "reloaded")
        sdk.onConfigurationLoaded = { _ in reloaded.fulfill() }
        sdk.updateParameters(["customerId": "2022"])
        wait(for: [reloaded], timeout: 5)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(sdk.currentParameters, ["customerId": "2022"])
    }

    func testDeepLinkAndSessionData() {
        let sdk = makeSDK(transport: MockTransport([]))
        sdk.handle(url: URL(string: "surveytest://open?campaign=summer")!)
        sdk.setSessionData("WELCOME10", forKey: "promo_code")
        XCTAssertEqual(sdk.core.resolver.value(source: .url, key: "campaign", name: "x"), "summer")
        XCTAssertEqual(sdk.core.resolver.value(source: .session, key: "promo_code", name: "x"), "WELCOME10")
        sdk.resetSessionData()
        XCTAssertNil(sdk.core.resolver.value(source: .session, key: "promo_code", name: "x"))
    }

    /// Cold start from a link: the link arrives before `initialize` and must not be lost.
    func testDeepLinkBeforeInitializeIsAppliedOnStart() {
        MobileSDK.setShared(nil)
        MobileSDK.handle(url: URL(string: "surveytest://open?campaign=summer")!)
        XCTAssertEqual(MobileSDK.pendingURL?.absoluteString, "surveytest://open?campaign=summer")

        let sdk = makeSDK(transport: MockTransport([]))   // installs `shared` like initialize
        XCTAssertNil(MobileSDK.pendingURL)
        XCTAssertEqual(sdk.core.resolver.value(source: .url, key: "campaign", name: "x"), "summer")
    }

    /// With the SDK running, the static entry point goes straight to the instance.
    func testStaticDeepLinkAfterInitialize() {
        let sdk = makeSDK(transport: MockTransport([]))
        MobileSDK.handle(url: URL(string: "surveytest://open?campaign=winter")!)
        XCTAssertNil(MobileSDK.pendingURL)
        XCTAssertEqual(sdk.core.resolver.value(source: .url, key: "campaign", name: "x"), "winter")
    }

    /// Only the latest early link is kept.
    func testLatestEarlyDeepLinkWins() {
        MobileSDK.setShared(nil)
        MobileSDK.handle(url: URL(string: "surveytest://open?campaign=first")!)
        MobileSDK.handle(url: URL(string: "surveytest://open?campaign=second")!)
        let sdk = makeSDK(transport: MockTransport([]))
        XCTAssertEqual(sdk.core.resolver.value(source: .url, key: "campaign", name: "x"), "second")
    }

    func testShutdownStopsIntegration() {
        let sdk = makeSDK(transport: MockTransport([]))
        sdk.autoSetup()
        sdk.shutdown()
        XCTAssertTrue(integration.stopped)
        XCTAssertNil(MobileSDK.shared)
    }
}

final class SupportTests: XCTestCase {
    func testHexColors() {
        XCTAssertEqual(RGBAColor(hex: "#FFFFFF"), .white)
        XCTAssertEqual(RGBAColor(hex: "#000000"), RGBAColor(red: 0, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(RGBAColor(hex: "F00"), RGBAColor(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(RGBAColor(hex: "#00FF0000"), RGBAColor(red: 1, green: 0, blue: 0, alpha: 0), "Android order: #AARRGGBB")
        XCTAssertEqual(RGBAColor(hex: "red"), .white)
        XCTAssertEqual(RGBAColor(hex: "#12345"), .white)
    }

    func testModalStyleAndAnimation() {
        XCTAssertEqual(SurveyModalStyle(configValue: "dialog"), .dialog)
        XCTAssertEqual(SurveyModalStyle(configValue: "BOTTOM_SHEET"), .bottomSheet)
        XCTAssertEqual(SurveyModalStyle(configValue: "popup"), .fullScreen)
        XCTAssertEqual(SurveyAnimation(configValue: "fade"), .fade)
        XCTAssertEqual(SurveyAnimation(configValue: "zoom"), .slideUp)
    }

    func testLinkPolicy() {
        XCTAssertEqual(SurveyLinkPolicy.decision(for: URL(string: "https://cx.cloud4feed.com/?c=1")!), .load)
        XCTAssertEqual(SurveyLinkPolicy.decision(for: URL(string: "http://short.link/x")!), .load)
        XCTAssertEqual(SurveyLinkPolicy.decision(for: URL(string: "about:blank")!), .load)
        XCTAssertEqual(SurveyLinkPolicy.decision(for: URL(string: "mailto:a@b.com")!), .openExternally)
        XCTAssertEqual(SurveyLinkPolicy.decision(for: URL(string: "tel:+905551112233")!), .openExternally)
        XCTAssertEqual(SurveyLinkPolicy.decision(for: URL(string: "itms-apps://apps.apple.com/app/id1")!), .openExternally)
        XCTAssertEqual(SurveyLinkPolicy.decision(for: URL(string: "https://apps.apple.com/app/id1")!), .openExternally)
    }

    func testScreenNameFilter() {
        XCTAssertTrue(ScreenNameFilter.isSystemClassName("UIViewController"))
        XCTAssertTrue(ScreenNameFilter.isSystemClassName("UIHostingController<ContentView>"))
        XCTAssertTrue(ScreenNameFilter.isSystemClassName("_UIRemoteInputViewController"))
        XCTAssertTrue(ScreenNameFilter.isSystemClassName("SFSafariViewController"))
        XCTAssertTrue(ScreenNameFilter.isSystemClassName("SurveyViewController"))
        XCTAssertFalse(ScreenNameFilter.isSystemClassName("HomeViewController"))
        XCTAssertFalse(ScreenNameFilter.isSystemClassName("CartViewController"))
        XCTAssertFalse(ScreenNameFilter.isSystemClassName("UserProfileViewController"))
    }
}
