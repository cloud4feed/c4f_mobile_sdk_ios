import XCTest
@testable import Cloud4FeedSDK

final class EligibilityTests: XCTestCase {
    private var env: TestEnvironment!
    private var core: SDKCore!

    override func setUp() {
        SDKLog.isEnabled = false
        env = TestEnvironment()
        core = env.makeCore(parameters: ["customerId": "1011"])
    }

    override func tearDown() { env.cleanUp() }

    private var eligibility: Eligibility { core.eligibility }

    func testStatusAndBaseUrl() {
        XCTAssertEqual(eligibility.decision(for: survey { $0.status = false }), .blocked(.disabled))
        XCTAssertEqual(eligibility.decision(for: survey { $0.baseUrl = "" }), .blocked(.emptyBaseUrl))
        XCTAssertEqual(eligibility.decision(for: survey()), .allowed)
    }

    func testExclusionRules() {
        env.appStore.set("male", forKey: "gender")
        let excluded = survey {
            $0.exclusionRules = [ExclusionRule(name: "gender", source: .storage, ruleOperator: .equals, matchValue: "male")]
        }
        XCTAssertEqual(eligibility.decision(for: excluded), .blocked(.excluded))
    }

    func testMaxShowsPerSession() {
        let limited = survey { $0.maxShowsPerSession = 2 }
        eligibility.recordShown(limited)
        XCTAssertTrue(eligibility.canShow(limited))
        eligibility.recordShown(limited)
        XCTAssertEqual(eligibility.decision(for: limited), .blocked(.maxShowsReached))

        eligibility.resetSessionCounters()
        XCTAssertTrue(eligibility.canShow(limited), "counters restart when a config is applied")

        let unlimited = survey("2") { $0.maxShowsPerSession = 0 }
        for _ in 0..<10 { eligibility.recordShown(unlimited) }
        XCTAssertTrue(eligibility.canShow(unlimited))
    }

    func testCooldown() {
        let cooled = survey { $0.cooldownPeriod = 60_000 }
        XCTAssertTrue(eligibility.canShow(cooled), "never shown -> no cooldown")
        eligibility.recordShown(cooled)
        env.clock.advance(seconds: 59)
        XCTAssertEqual(eligibility.decision(for: cooled), .blocked(.cooldown))
        env.clock.advance(seconds: 1)
        XCTAssertTrue(eligibility.canShow(cooled))
    }

    func testTriggerOncePerUserAndPersistent() {
        let once = survey { $0.triggerOnce = true }
        eligibility.recordShown(once)
        XCTAssertEqual(eligibility.decision(for: once), .blocked(.alreadyShownOnce))

        eligibility.resetSessionCounters()
        XCTAssertEqual(eligibility.decision(for: once), .blocked(.alreadyShownOnce), "survives config reloads")

        // Next app launch, same user: still blocked (persisted).
        let sameUser = env.makeCore(parameters: ["customerId": "1011"])
        XCTAssertEqual(sameUser.eligibility.decision(for: once), .blocked(.alreadyShownOnce))

        // Another user on the same device sees it.
        let otherUser = env.makeCore(parameters: ["customerId": "2022"])
        XCTAssertTrue(otherUser.eligibility.canShow(once))

        eligibility.clearTriggerOnceHistory()
        XCTAssertTrue(sameUser.eligibility.canShow(once))
    }

    func testTriggerOnceIgnoredForBlankId() {
        let noId = survey("") { $0.triggerOnce = true }
        eligibility.recordShown(noId)
        XCTAssertTrue(eligibility.canShow(noId))
    }

    func testProbabilityIsNotApplied() {
        XCTAssertTrue(eligibility.canShow(survey { $0.probability = 0 }))
    }

    func testStableHashIsOrderIndependentAndStable() {
        XCTAssertEqual(StableHash.parameters(["a": "1", "b": "2"]), StableHash.parameters(["b": "2", "a": "1"]))
        XCTAssertNotEqual(StableHash.parameters(["a": "1"]), StableHash.parameters(["a": "2"]))
        XCTAssertEqual(StableHash.fnv1a64(""), "cbf29ce484222325")
        XCTAssertEqual(StableHash.fnv1a64("a"), "af63dc4c8601ec8c")
    }
}
