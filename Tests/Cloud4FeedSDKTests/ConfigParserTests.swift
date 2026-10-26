import XCTest
@testable import Cloud4FeedSDK

final class ConfigParserTests: XCTestCase {
    override func setUp() {
        SDKLog.isEnabled = false
        ConfigParser.makeFallbackSurveyId = { "generated" }
    }

    func testParsesRealResponseShape() throws {
        let config = ConfigParser.parseResponse(Data(Fixtures.response.utf8))

        XCTAssertEqual(config.sdkVersion, "2.0.18")
        XCTAssertEqual(config.cacheDurationHours, 0)
        XCTAssertEqual(config.surveys.count, 2, "non-object entries are skipped")

        let first = config.surveys[0]
        XCTAssertEqual(first.surveyId, "180")
        XCTAssertEqual(first.surveyName, "Lacoste")
        XCTAssertEqual(first.baseUrl, "https://cx.cloud4feed.com/?c=5qZu-abc")
        XCTAssertTrue(first.status)
        XCTAssertTrue(first.enableButtonTrigger)
        XCTAssertEqual(first.buttonTriggerId, "checkout_button")
        XCTAssertTrue(first.enableNavigationTrigger)
        XCTAssertFalse(first.enableScrollTrigger)
        XCTAssertEqual(first.triggerScreens, ["home", "cart"], "null entries are skipped")
        XCTAssertEqual(first.triggerTabs, ["womens"])
        XCTAssertEqual(first.timeDelay, 1500, "numeric strings are accepted")
        XCTAssertEqual(first.scrollThreshold, 800)
        XCTAssertEqual(first.triggerType, "delayed")
        XCTAssertEqual(first.modalStyle, "bottom_sheet")
        XCTAssertEqual(first.animationType, "fade")
        XCTAssertEqual(first.backgroundColor, "#000000")
        XCTAssertEqual(first.probability, 0.5)
        XCTAssertEqual(first.maxShowsPerSession, 2)
        XCTAssertEqual(first.cooldownPeriod, 60000)
        XCTAssertTrue(first.triggerOnce, "\"true\" string is accepted")
        XCTAssertEqual(first.priority, 3, "priority may be a string")
    }

    func testDefaultsForMissingFields() throws {
        let config = ConfigParser.parseResponse(Data(Fixtures.response.utf8))
        let second = config.surveys[1]

        XCTAssertEqual(second.surveyId, "generated", "missing surveyId gets a generated id")
        XCTAssertEqual(second.priority, 2)
        XCTAssertTrue(second.status)
        XCTAssertNil(second.buttonTriggerId)
        XCTAssertEqual(second.triggerType, "instant")
        XCTAssertEqual(second.modalStyle, "full_screen")
        XCTAssertEqual(second.animationType, "slide_up")
        XCTAssertEqual(second.backgroundColor, "#FFFFFF")
        XCTAssertEqual(second.probability, 1.0)
        XCTAssertEqual(second.maxShowsPerSession, 0)
        XCTAssertEqual(second.cooldownPeriod, 0)
        XCTAssertFalse(second.triggerOnce)
        XCTAssertTrue(second.customParams.isEmpty)
        XCTAssertTrue(second.exclusionRules.isEmpty)
    }

    func testCustomParamsSkipInvalidEntries() {
        let params = ConfigParser.parseResponse(Data(Fixtures.response.utf8)).surveys[0].customParams
        XCTAssertEqual(params, [
            CustomParam(name: "param_1", source: .storage, key: "customerId"),
            CustomParam(name: "param_2", source: .session, key: "current_screen"),
        ])
    }

    func testExclusionRuleOperatorsInEveryForm() {
        let rules = ConfigParser.parseResponse(Data(Fixtures.response.utf8)).surveys[0].exclusionRules
        XCTAssertEqual(rules.count, 4, "unknown source drops the rule")
        XCTAssertEqual(rules[0].ruleOperator, .equals)
        XCTAssertEqual(rules[0].key, "user_tier")
        XCTAssertEqual(rules[0].matchValue, "gold")
        XCTAssertFalse(rules[0].caseSensitive)
        XCTAssertEqual(rules[1].ruleOperator, .notEquals, "Android enum name in `operator` field")
        XCTAssertEqual(rules[2].ruleOperator, .contains, "numeric string id")
        XCTAssertNil(rules[2].key)
        XCTAssertEqual(rules[3].ruleOperator, .startsWith, "backend spelling")
    }

    func testOperatorFallbacks() {
        XCTAssertEqual(ConfigParser.parseOperator(["ruleOperator": .number(99)]), .equals)
        XCTAssertEqual(ConfigParser.parseOperator(["ruleOperator": .string("whatever")]), .equals)
        XCTAssertEqual(ConfigParser.parseOperator([:]), .equals)
        XCTAssertEqual(ConfigParser.parseOperator(["ruleOperator": .null, "operator": .number(3)]), .equals,
                       "ruleOperator wins when present, even if null (Android behaviour)")
        XCTAssertEqual(ConfigParser.parseOperator(["operator": .number(4)]), .notIn)
        for op in ExclusionOperator.allCases {
            XCTAssertEqual(ConfigParser.parseOperator(["ruleOperator": .number(Double(op.rawValue))]), op)
        }
    }

    func testBackendErrorMessageGivesEmptyConfig() {
        let json = #"{"success": false, "messages": [{"success": false, "message": "Invalid api key"}], "data": {"surveys": [{"surveyId": "1"}]}}"#
        XCTAssertEqual(ConfigParser.parseResponse(Data(json.utf8)), .empty)
    }

    func testDirectConfigWithoutDataWrapper() {
        let json = #"{"sdkVersion": "2.0.0", "cacheDurationHours": 12, "surveys": [{"surveyId": "7", "baseUrl": "https://x/?c=1"}]}"#
        let config = ConfigParser.parseResponse(Data(json.utf8))
        XCTAssertEqual(config.cacheDurationHours, 12)
        XCTAssertEqual(config.surveys.map(\.surveyId), ["7"])
    }

    func testMissingOrNullSurveysGivesEmptyConfig() {
        XCTAssertEqual(ConfigParser.parseResponse(Data(#"{"data": {"surveys": null}}"#.utf8)), .empty)
        XCTAssertEqual(ConfigParser.parseResponse(Data(#"{"data": {}}"#.utf8)), .empty)
        XCTAssertEqual(ConfigParser.parseResponse(Data("not json".utf8)), .empty)
        XCTAssertEqual(ConfigParser.parseResponse(Data("[]".utf8)), .empty)
    }

    func testNullSdkVersionUsesDefault() {
        let config = ConfigParser.parseResponse(Data(#"{"data": {"sdkVersion": null, "surveys": []}}"#.utf8))
        XCTAssertEqual(config.sdkVersion, SDKConstants.sdkVersion)
        XCTAssertEqual(config.cacheDurationHours, 24)
    }

    func testEncodeRoundTrip() throws {
        let original = ConfigParser.parseResponse(Data(Fixtures.response.utf8))
        let encoded = try ConfigParser.encode(original).serialized()
        let decoded = try XCTUnwrap(ConfigParser.parseConfigObject(try JSONValue.parse(encoded).objectValue ?? [:]))
        XCTAssertEqual(decoded, original)
    }
}
