import XCTest
@testable import Cloud4FeedSDK

final class SurveyEngineTests: XCTestCase {
    private var env: TestEnvironment!
    private var core: SDKCore!
    private var engine: SurveyEngine { core.engine }

    override func setUp() {
        SDKLog.isEnabled = false
        env = TestEnvironment()
        core = env.makeCore()
    }

    override func tearDown() { env.cleanUp() }

    private func apply(_ surveys: [SurveyConfig]) {
        engine.apply(Config(surveys: surveys))
    }

    // MARK: Navigation

    func testNavigationMatching() {
        apply([
            survey("home") { $0.enableNavigationTrigger = true; $0.triggerScreens = ["home"] },
            survey("any") { $0.enableNavigationTrigger = true },
            survey("off") { $0.triggerScreens = ["home"] },
        ])
        XCTAssertEqual(engine.screenDidAppear("HomeViewController").map(\.surveyId), ["home", "any"],
                       "case-insensitive contains")
        XCTAssertEqual(engine.screenDidAppear("ho").map(\.surveyId), ["home", "any"],
                       "reverse direction: the configured name contains the screen name (Android)")
        XCTAssertEqual(engine.screenDidAppear("cart").map(\.surveyId), ["any"])
        XCTAssertEqual(core.session.currentScreen, "cart")
        XCTAssertEqual(core.session.screenViewCount, 3)
    }

    func testSurveyScreensAreIgnored() {
        apply([survey { $0.enableNavigationTrigger = true }])
        core.session.currentScreen = "home"
        XCTAssertTrue(engine.screenDidAppear("SurveyWebViewController").isEmpty)
        XCTAssertEqual(core.session.currentScreen, "home", "the SDK's own screen does not change the context")
    }

    func testCurrentScreenSurvivesConfigReload() {
        _ = engine.screenDidAppear("womens")
        apply([])
        XCTAssertEqual(core.resolver.value(source: .session, key: "current_screen", name: "x"), "womens")
    }

    // MARK: Exit

    func testExitMatching() {
        apply([
            survey("cartExit") { $0.enableExitTrigger = true; $0.triggerScreens = ["cart"] },
            survey("noScreens") { $0.enableExitTrigger = true },
        ])
        XCTAssertEqual(engine.exitSurveys(leaving: "CartScreen", to: "home").map(\.surveyId), ["cartExit"])
        XCTAssertTrue(engine.exitSurveys(leaving: "home", to: "cart").isEmpty)
        XCTAssertTrue(engine.exitSurveys(leaving: "cart", to: "SurveyScreen").isEmpty)
    }

    // MARK: Button

    func testButtonSpecificBeatsGeneric() {
        apply([
            survey("generic") { $0.enableButtonTrigger = true },
            survey("low") { $0.enableButtonTrigger = true; $0.buttonTriggerId = "checkout_button"; $0.priority = 1 },
            survey("high") { $0.enableButtonTrigger = true; $0.buttonTriggerId = "checkout_button"; $0.priority = 5 },
        ])
        XCTAssertEqual(engine.buttonSurvey(for: "checkout_button")?.surveyId, "high")
        XCTAssertEqual(engine.buttonSurvey(for: "survey_button")?.surveyId, "generic")
        XCTAssertNil(engine.buttonSurvey(for: "random_button"))
        XCTAssertEqual(engine.watchedButtonIds, Set(["checkout_button"] + SDKConstants.predefinedButtonIds))
    }

    func testButtonBlockedByRules() {
        apply([survey { $0.enableButtonTrigger = true; $0.buttonTriggerId = "b"; $0.status = false }])
        XCTAssertNil(engine.buttonSurvey(for: "b"))
    }

    // MARK: Tab

    func testTabExactMatch() {
        apply([
            survey("mens") { $0.enableTabChangeTrigger = true; $0.triggerTabs = ["mens"] },
            survey("womens") { $0.enableTabChangeTrigger = true; $0.triggerTabs = ["Womens "] },
        ])
        XCTAssertEqual(engine.tabSurvey(for: "womens")?.surveyId, "womens", "'mens' must not match 'womens'")
        XCTAssertEqual(engine.tabSurvey(for: "tab_mens")?.surveyId, "mens")
        XCTAssertNil(engine.tabSurvey(for: "kids"))
        XCTAssertEqual(core.session.currentScreen, "kids", "the tab becomes the current context")
    }

    // MARK: Scroll

    func testScrollRespectsThresholdAndScreens() {
        apply([
            survey("scoped") { $0.enableScrollTrigger = true; $0.scrollThreshold = 500; $0.triggerScreens = ["womens"]; $0.priority = 2 },
            survey("anywhere") { $0.enableScrollTrigger = true; $0.scrollThreshold = 1000 },
        ])
        XCTAssertTrue(engine.hasScrollSurveys)

        core.session.currentScreen = "home"
        XCTAssertNil(engine.scrollSurvey(offsetPixels: 600), "scoped survey must not fire on another screen (v2.0.18 fix)")
        XCTAssertEqual(engine.scrollSurvey(offsetPixels: 1200)?.surveyId, "anywhere")

        core.session.currentScreen = "womens"
        XCTAssertNil(engine.scrollSurvey(offsetPixels: 499))
        XCTAssertEqual(engine.scrollSurvey(offsetPixels: 1200)?.surveyId, "scoped", "higher priority wins")
        XCTAssertEqual(engine.scrollSurvey(offsetPixels: 600, screenName: "home"), nil)
    }

    // MARK: App launch / timing

    func testAppLaunchAndDelay() {
        let delayed = survey("delayed") { $0.enableAppLaunchTrigger = true; $0.triggerType = "delayed"; $0.timeDelay = 1500 }
        apply([delayed, survey("instant") { $0.enableAppLaunchTrigger = true; $0.timeDelay = 1500 }, survey("no")])
        XCTAssertEqual(engine.appLaunchSurveys().map(\.surveyId), ["delayed", "instant"])
        XCTAssertEqual(SurveyEngine.delay(for: delayed), 1.5)
        XCTAssertEqual(SurveyEngine.delay(for: engine.config.surveys[1]), 0, "instant ignores timeDelay")
    }

    func testPriorityTieKeepsConfigOrder() {
        let surveys = [survey("a") { $0.priority = 2 }, survey("b") { $0.priority = 2 }, survey("c") { $0.priority = 1 }]
        XCTAssertEqual(SurveyEngine.highestPriority(surveys)?.surveyId, "a")
    }

    func testRecordShownFeedsLimits() {
        let limited = survey { $0.enableButtonTrigger = true; $0.maxShowsPerSession = 1 }
        apply([limited])
        XCTAssertNotNil(engine.buttonSurvey(for: "survey_button"))
        engine.recordShown(limited)
        XCTAssertNil(engine.buttonSurvey(for: "survey_button"))
        apply([limited])
        XCTAssertNotNil(engine.buttonSurvey(for: "survey_button"), "a new config restarts session counters")
    }

    func testTurkishLocaleDoesNotBreakMatching() {
        XCTAssertTrue("HOME_SCREEN".c4fContainsIgnoringCase("home"))
        XCTAssertTrue("İstanbul".c4fContainsIgnoringCase("İstanbul"))
        XCTAssertTrue("anything".c4fContainsIgnoringCase(""))
    }
}
