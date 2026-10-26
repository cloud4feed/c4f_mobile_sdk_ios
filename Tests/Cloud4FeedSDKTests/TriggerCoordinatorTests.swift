import XCTest
@testable import Cloud4FeedSDK

final class TriggerCoordinatorTests: XCTestCase {
    private var env: TestEnvironment!

    override func setUp() {
        SDKLog.isEnabled = false
        env = TestEnvironment()
    }

    override func tearDown() { env.cleanUp() }

    // MARK: Screens

    func testNavigationAndExitInPriorityOrder() {
        let (_, coordinator, presenter, scheduler) = env.makeCoordinator([
            survey("homeExit") { $0.enableExitTrigger = true; $0.triggerScreens = ["home"]; $0.priority = 1 },
            survey("notif") { $0.enableNavigationTrigger = true; $0.triggerScreens = ["notifications"]; $0.priority = 1 },
        ])
        coordinator.trackScreen("Home")
        XCTAssertTrue(presenter.presented.isEmpty)

        coordinator.trackScreen("Notifications")
        XCTAssertEqual(presenter.presentedIds, ["homeExit"], "exit wins a priority tie, the other one waits")
        XCTAssertEqual(coordinator.queue.map(\.surveyId), ["notif"])

        presenter.closeCurrent()
        scheduler.advance(seconds: 0.5)
        XCTAssertEqual(presenter.presentedIds, ["homeExit", "notif"])
    }

    func testSameScreenTwiceDoesNotRetrigger() {
        let (core, coordinator, presenter, _) = env.makeCoordinator([
            survey { $0.enableNavigationTrigger = true; $0.triggerScreens = ["home"] },
        ])
        coordinator.trackScreen("home")
        presenter.closeCurrent()
        env.clock.advance(seconds: 5)
        coordinator.trackScreen("HOME ")
        XCTAssertEqual(presenter.presented.count, 1)
        XCTAssertEqual(core.session.screenViewCount, 1)
    }

    func testPostSurveyCooldownIgnoresScreens() {
        let (_, coordinator, presenter, _) = env.makeCoordinator([
            survey("a") { $0.enableNavigationTrigger = true; $0.triggerScreens = ["cart"] },
        ])
        coordinator.trackScreen("cart")
        presenter.closeCurrent()
        coordinator.trackScreen("home")
        env.clock.advance(seconds: 1)
        coordinator.trackScreen("cart")
        XCTAssertEqual(presenter.presented.count, 1, "within 2 s after closing")
        env.clock.advance(seconds: 1.5)
        coordinator.trackScreen("cart")
        XCTAssertEqual(presenter.presented.count, 1, "previous screen is still 'cart'")
        coordinator.trackScreen("home")
        coordinator.trackScreen("cart")
        XCTAssertEqual(presenter.presented.count, 2)
    }

    func testScreenBeforeConfigIsReplayed() {
        let (core, coordinator, presenter, _) = env.makeCoordinator()
        coordinator.trackScreen("Notifications")
        XCTAssertEqual(core.session.currentScreen, "notifications", "context is set at once")
        XCTAssertTrue(presenter.presented.isEmpty)

        core.engine.apply(Config(surveys: [survey { $0.enableNavigationTrigger = true; $0.triggerScreens = ["notifications"] }]))
        coordinator.configurationApplied()
        XCTAssertEqual(presenter.presented.count, 1)
    }

    func testDelayedNavigationIsCancelledWhenLeaving() {
        let (_, coordinator, presenter, scheduler) = env.makeCoordinator([
            survey("delayed") {
                $0.enableNavigationTrigger = true; $0.triggerScreens = ["home"]
                $0.triggerType = "delayed"; $0.timeDelay = 3000
            },
        ])
        coordinator.trackScreen("home")
        scheduler.advance(seconds: 2)
        XCTAssertTrue(presenter.presented.isEmpty)
        scheduler.advance(seconds: 1)
        XCTAssertEqual(presenter.presentedIds, ["delayed"])

        presenter.closeCurrent()
        scheduler.advance(seconds: 3)
        coordinator.trackScreen("cart")
        coordinator.trackScreen("home")
        scheduler.advance(seconds: 1)
        coordinator.trackScreen("cart")
        scheduler.advance(seconds: 5)
        XCTAssertEqual(presenter.presentedIds, ["delayed"], "left the screen before the delay ended")
    }

    func testSurveyScreensAreNotAppScreens() {
        let (core, coordinator, _, _) = env.makeCoordinator([])
        coordinator.trackScreen("home")
        coordinator.trackScreen("SurveyViewController")
        XCTAssertEqual(core.session.currentScreen, "home")
        XCTAssertEqual(coordinator.previousScreen, "home")
    }

    // MARK: Tabs

    func testTabDebounceAndContext() {
        let (core, coordinator, presenter, _) = env.makeCoordinator([
            survey("w") { $0.enableTabChangeTrigger = true; $0.triggerTabs = ["womens"] },
            survey("m") { $0.enableTabChangeTrigger = true; $0.triggerTabs = ["mens"] },
        ])
        coordinator.trackTab("Womens")
        XCTAssertEqual(presenter.presentedIds, ["w"])
        XCTAssertEqual(core.session.currentScreen, "womens")
        presenter.closeCurrent()

        env.clock.advance(seconds: 3)
        coordinator.trackTab("Mens")
        coordinator.trackTab("Womens")
        XCTAssertEqual(presenter.presentedIds, ["w", "m"], "second event within 1 s is ignored")
        XCTAssertEqual(core.session.currentScreen, "womens", "but the context still follows the tab")
    }

    // MARK: Buttons

    func testButtonBeforeConfigRetries() {
        let (core, coordinator, presenter, scheduler) = env.makeCoordinator()
        coordinator.triggerButton("survey_button")
        scheduler.advance(seconds: 1)
        XCTAssertTrue(presenter.presented.isEmpty)

        core.engine.apply(Config(surveys: [survey { $0.enableButtonTrigger = true }]))
        scheduler.advance(seconds: 1)
        XCTAssertEqual(presenter.presented.count, 1)
    }

    func testButtonDebounce() {
        let (_, coordinator, presenter, _) = env.makeCoordinator([
            survey("a") { $0.enableButtonTrigger = true; $0.buttonTriggerId = "a" },
            survey("b") { $0.enableButtonTrigger = true; $0.buttonTriggerId = "b" },
        ])
        coordinator.triggerButton("a")
        presenter.closeCurrent()
        coordinator.triggerButton("b")
        XCTAssertEqual(presenter.presentedIds, ["a"])
        env.clock.advance(seconds: 0.6)
        coordinator.triggerButton("b")
        XCTAssertEqual(presenter.presentedIds, ["a", "b"])
    }

    // MARK: Scroll

    func testScrollOncePerScreenAndRespectsScreens() {
        let (_, coordinator, presenter, scheduler) = env.makeCoordinator([
            survey("s") { $0.enableScrollTrigger = true; $0.scrollThreshold = 500; $0.triggerScreens = ["home"] },
        ])
        coordinator.trackScreen("notifications")
        coordinator.scrollChanged(offsetPixels: 900)
        XCTAssertTrue(presenter.presented.isEmpty, "scoped to home (v2.0.18)")

        coordinator.trackScreen("home")
        coordinator.scrollChanged(offsetPixels: 400)
        scheduler.advance(seconds: 0.1)
        coordinator.scrollChanged(offsetPixels: 600)
        XCTAssertTrue(presenter.presented.isEmpty, "throttled")
        scheduler.advance(seconds: 0.2)
        XCTAssertEqual(presenter.presentedIds, ["s"], "the last offset of the burst is evaluated")

        presenter.closeCurrent()
        scheduler.advance(seconds: 10)
        coordinator.scrollChanged(offsetPixels: 1200)
        XCTAssertEqual(presenter.presented.count, 1, "once per screen visit")

        coordinator.trackScreen("notifications")
        coordinator.trackScreen("home")
        coordinator.scrollChanged(offsetPixels: 1200)
        scheduler.advance(seconds: 0.2)
        XCTAssertEqual(presenter.presented.count, 2, "new visit, new chance")
    }

    // MARK: App launch / exit

    func testAppLaunchWaitsForConfigAndDelay() {
        let (core, coordinator, presenter, scheduler) = env.makeCoordinator()
        coordinator.appDidLaunch()
        core.engine.apply(Config(surveys: [
            survey("launch") { $0.enableAppLaunchTrigger = true; $0.triggerType = "delayed"; $0.timeDelay = 2000 },
        ]))
        coordinator.configurationApplied()
        XCTAssertTrue(presenter.presented.isEmpty)
        scheduler.advance(seconds: 2)
        XCTAssertEqual(presenter.presentedIds, ["launch"])

        presenter.closeCurrent()
        coordinator.configurationApplied()
        scheduler.advance(seconds: 5)
        XCTAssertEqual(presenter.presented.count, 1, "once per process, not per config reload")
    }

    func testAppExitShowsOnReturn() {
        let surveys = [
            survey("appExit") { $0.enableExitTrigger = true },
            survey("screenExit") { $0.enableExitTrigger = true; $0.triggerScreens = ["cart"] },
        ]
        let (_, coordinator, presenter, scheduler) = env.makeCoordinator(surveys)
        coordinator.appDidEnterBackground()
        XCTAssertEqual(env.exitStore.object(forKey: "pending_surveys") as? [String], ["appExit"])

        coordinator.appWillEnterForeground()
        XCTAssertNil(env.exitStore.object(forKey: "pending_surveys"))
        scheduler.advance(seconds: 1.5)
        XCTAssertEqual(presenter.presentedIds, ["appExit"])
    }

    func testAppExitFromLastSessionShowsAtNextLaunch() {
        env.exitStore.set(["appExit"], forKey: "pending_surveys")
        let (core, coordinator, presenter, scheduler) = env.makeCoordinator()
        coordinator.appDidLaunch()
        core.engine.apply(Config(surveys: [survey("appExit") { $0.enableExitTrigger = true }]))
        coordinator.configurationApplied()
        scheduler.advance(seconds: 1.5)
        XCTAssertEqual(presenter.presentedIds, ["appExit"])
    }

    // MARK: Queue

    func testQueueIsPriorityOrderedWithoutDuplicates() {
        let (_, coordinator, presenter, scheduler) = env.makeCoordinator([
            survey("first"), survey("low") { $0.priority = 1 }, survey("high") { $0.priority = 9 },
        ])
        coordinator.showSurvey(id: "first")
        coordinator.showSurvey(id: "low")
        coordinator.showSurvey(id: "high")
        coordinator.showSurvey(id: "low")
        coordinator.showSurvey(id: "first")
        XCTAssertEqual(coordinator.queue.map(\.surveyId), ["high", "low"])

        presenter.closeCurrent()
        scheduler.advance(seconds: 0.5)
        presenter.closeCurrent()
        scheduler.advance(seconds: 0.5)
        XCTAssertEqual(presenter.presentedIds, ["first", "high", "low"])
    }

    func testQueuedSurveyIsRecheckedBeforeShowing() {
        let (core, coordinator, presenter, scheduler) = env.makeCoordinator([
            survey("a"), survey("b") { $0.maxShowsPerSession = 1 },
        ])
        coordinator.showSurvey(id: "b")
        presenter.closeCurrent()
        env.clock.advance(seconds: 3)
        coordinator.showSurvey(id: "a")
        coordinator.show(core.engine.survey(withId: "b")!) // queued without checking the rules
        presenter.closeCurrent()
        scheduler.advance(seconds: 1)
        XCTAssertEqual(presenter.presentedIds, ["b", "a"], "b reached its limit while waiting")
    }

    func testFailedPresentationReleasesTheQueue() {
        let (_, coordinator, presenter, _) = env.makeCoordinator([survey("a")])
        presenter.canPresent = false
        XCTAssertTrue(coordinator.showSurvey(id: "a"))
        XCTAssertFalse(coordinator.isShowingSurvey)
        presenter.canPresent = true
        coordinator.showSurvey(id: "a")
        XCTAssertEqual(presenter.presentedIds, ["a"])
    }

    func testPresentationRequestCarriesDisplaySettings() {
        let (_, coordinator, presenter, _) = env.makeCoordinator([
            survey("a") { $0.modalStyle = "bottom_sheet"; $0.animationType = "fade"; $0.backgroundColor = "#80FF0000" },
        ])
        coordinator.showSurvey(id: "a")
        let request = presenter.presented.first
        XCTAssertEqual(request?.style, .bottomSheet)
        XCTAssertEqual(request?.animation, .fade)
        XCTAssertEqual(request?.backgroundColor, RGBAColor(red: 1, green: 0, blue: 0, alpha: 128.0 / 255))
        XCTAssertEqual(request?.url, "https://cx.cloud4feed.com/?c=codea")
    }
}
