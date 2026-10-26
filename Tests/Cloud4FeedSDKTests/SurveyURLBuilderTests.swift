import XCTest
@testable import Cloud4FeedSDK

final class SurveyURLBuilderTests: XCTestCase {
    override func setUp() { SDKLog.isEnabled = false }

    func testAppendsParametersLikeAndroid() {
        let url = SurveyURLBuilder.build(baseUrl: "https://cx.cloud4feed.com/?c=5qZu-abc",
                                         parameters: [(name: "param_1", value: "1011"), (name: "param_5", value: "womens")])
        XCTAssertEqual(url, "https://cx.cloud4feed.com/?c=5qZu-abc&param_1=1011&param_5=womens")
    }

    func testNoParametersKeepsBaseUrl() {
        XCTAssertEqual(SurveyURLBuilder.build(baseUrl: "https://cx.cloud4feed.com/?c=x", parameters: []),
                       "https://cx.cloud4feed.com/?c=x")
    }

    func testSeparatorWhenBaseHasNoQuery() {
        XCTAssertEqual(SurveyURLBuilder.build(baseUrl: "https://c4f.link/abc", parameters: [(name: "a", value: "1")]),
                       "https://c4f.link/abc?a=1")
        XCTAssertEqual(SurveyURLBuilder.build(baseUrl: "https://x/?", parameters: [(name: "a", value: "1")]),
                       "https://x/?a=1")
    }

    func testEncodingOnlyWhereNeeded() {
        XCTAssertEqual(SurveyURLBuilder.encode("user@mail.com"), "user@mail.com")
        XCTAssertEqual(SurveyURLBuilder.encode("2025-10-05 13:07"), "2025-10-05%2013:07")
        XCTAssertEqual(SurveyURLBuilder.encode("a&b=c#d"), "a%26b%3Dc%23d")
        XCTAssertEqual(SurveyURLBuilder.encode("İstanbul"), "%C4%B0stanbul")
        XCTAssertEqual(SurveyURLBuilder.encode("a+b/c:d"), "a+b/c:d")
        let url = SurveyURLBuilder.build(baseUrl: "https://x/?c=1", parameters: [(name: "city", value: "New York")])
        XCTAssertNotNil(URL(string: url), "result is always a valid URL")
    }

    func testCollectorOrderSkipAndOverride() {
        let env = TestEnvironment(device: ["deviceID": "ABC", "platform": "iOS", "latitude": "41.0", "longitude": "29.0"])
        defer { env.cleanUp() }
        let core = env.makeCore()
        core.setUserProperty("1011", forKey: "customerId")
        core.session.currentScreen = "womens"

        let configured = survey("180") {
            $0.customParams = [
                CustomParam(name: "param_1", source: .storage, key: "customerId"),
                CustomParam(name: "missing", source: .storage, key: "nope"),
                CustomParam(name: "param_5", source: .session, key: "current_screen"),
                CustomParam(name: "platform", source: .storage, key: "customerId"),
            ]
            $0.collectDeviceId = true
            $0.collectLocation = true
        }
        let pairs = core.engine.collector.parameters(for: configured)
        XCTAssertEqual(pairs.map(\.name), ["param_1", "param_5", "platform", "deviceID", "latitude", "longitude"])
        XCTAssertEqual(pairs.first { $0.name == "platform" }?.value, "iOS",
                       "device info replaces an earlier value but keeps its position")

        XCTAssertEqual(core.engine.surveyURL(for: configured),
                       "https://cx.cloud4feed.com/?c=code180&param_1=1011&param_5=womens&platform=iOS&deviceID=ABC&latitude=41.0&longitude=29.0")
    }
}
