import XCTest
@testable import Cloud4FeedSDK

final class ExclusionEvaluatorTests: XCTestCase {
    override func setUp() { SDKLog.isEnabled = false }

    private func match(_ actual: String, _ op: ExclusionOperator, _ value: String, caseSensitive: Bool = false) -> Bool {
        ExclusionEvaluator.matches(actual: actual, operator: op, matchValue: value, caseSensitive: caseSensitive)
    }

    func testTextOperators() {
        XCTAssertTrue(match("Gold", .equals, "gold"))
        XCTAssertFalse(match("Gold", .equals, "gold", caseSensitive: true))
        XCTAssertTrue(match("Gold", .notEquals, "silver"))
        XCTAssertFalse(match("gold", .notEquals, "GOLD"))
        XCTAssertTrue(match("premium_gold", .contains, "GOLD"))
        XCTAssertTrue(match("abc", .contains, ""), "empty match value is contained (Kotlin)")
        XCTAssertTrue(match("premium", .notContains, "gold"))
        XCTAssertTrue(match("Ankara", .startsWith, "an"))
        XCTAssertTrue(match("Ankara", .endsWith, "RA"))
        XCTAssertFalse(match("Ankara", .startsWith, "an", caseSensitive: true))
    }

    func testListOperators() {
        XCTAssertTrue(match("Ankara", .`in`, "istanbul, ankara ,izmir"))
        XCTAssertFalse(match("Bursa", .`in`, "istanbul,ankara"))
        XCTAssertTrue(match("Bursa", .notIn, "istanbul,ankara"))
        XCTAssertFalse(match("Ankara", .`in`, "ankara", caseSensitive: true))
        XCTAssertTrue(match("Ankara", .`in`, "Ankara", caseSensitive: true))
    }

    func testNumericOperators() {
        XCTAssertTrue(match("10", .greaterThan, "5"))
        XCTAssertFalse(match("5", .greaterThan, "5"))
        XCTAssertTrue(match("5", .greaterOrEqual, "5"))
        XCTAssertTrue(match("4.5", .lessThan, "5"))
        XCTAssertTrue(match("5", .lessOrEqual, "5.0"))
        XCTAssertFalse(match("abc", .greaterThan, "1"), "non-numeric value never matches")
        XCTAssertFalse(match("", .lessThan, "1"), "missing value never matches")
        XCTAssertTrue(match("12345", .length, "5"))
        XCTAssertFalse(match("1234", .length, "5"))
    }

    func testEmptyOperators() {
        XCTAssertTrue(match("", .empty, ""))
        XCTAssertTrue(match("   ", .empty, ""))
        XCTAssertFalse(match("x", .empty, ""))
        XCTAssertTrue(match("x", .notEmpty, ""))
        XCTAssertFalse(match(" ", .notEmpty, ""))
    }

    func testRulesUseValueSources() {
        let env = TestEnvironment(device: ["osVersion": "17.4"])
        defer { env.cleanUp() }
        let core = env.makeCore()
        let evaluator = ExclusionEvaluator(resolver: core.resolver)

        env.appStore.set("gold", forKey: "user_tier")
        core.setSessionData("WELCOME10", forKey: "promo_code")

        let tierRule = ExclusionRule(name: "tier", source: .storage, key: "user_tier", ruleOperator: .equals, matchValue: "GOLD")
        let promoRule = ExclusionRule(name: "promo_code", source: .session, ruleOperator: .startsWith, matchValue: "welcome")
        let osRule = ExclusionRule(name: "os", source: .device, key: "osVersion", ruleOperator: .startsWith, matchValue: "16")
        let missingRule = ExclusionRule(name: "missing", source: .storage, ruleOperator: .notEmpty)

        XCTAssertTrue(evaluator.evaluate(tierRule))
        XCTAssertTrue(evaluator.evaluate(promoRule), "key falls back to the rule name")
        XCTAssertFalse(evaluator.evaluate(osRule))
        XCTAssertFalse(evaluator.evaluate(missingRule), "missing value is an empty string")

        XCTAssertTrue(evaluator.shouldExclude([osRule, tierRule]), "one matching rule is enough")
        XCTAssertFalse(evaluator.shouldExclude([osRule, missingRule]))
        XCTAssertFalse(evaluator.shouldExclude([]))
    }
}
