import XCTest
@testable import Cloud4FeedSDK

final class SDKCoreTests: XCTestCase {
    private var env: TestEnvironment!

    override func setUp() {
        SDKLog.isEnabled = false
        env = TestEnvironment()
    }

    override func tearDown() { env.cleanUp() }

    private let cachedResponse = #"{"data": {"cacheDurationHours": 24, "surveys": [{"surveyId": "1", "baseUrl": "https://x/?c=1"}]}}"#

    func testNetworkThenCache() async {
        let transport = MockTransport([.response(status: 200, body: cachedResponse)])
        let core = env.makeCore(parameters: ["customerId": "1011"], transport: transport)

        let firstSource = await core.loadConfiguration()
        XCTAssertEqual(firstSource, .network)
        XCTAssertTrue(core.engine.isConfigLoaded)
        XCTAssertEqual(core.engine.config.surveys.map(\.surveyId), ["1"])

        let secondSource = await core.loadConfiguration()
        XCTAssertEqual(secondSource, .cache)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testNewParametersSkipCache() async {
        let transport = MockTransport([.response(status: 200, body: cachedResponse),
                                       .response(status: 200, body: cachedResponse)])
        let core = env.makeCore(parameters: ["customerId": "1011"], transport: transport)
        await core.loadConfiguration()

        core.updateParameters(["customerId": "2022"])
        let source = await core.loadConfiguration()
        XCTAssertEqual(source, .network)
        XCTAssertEqual(core.eligibility.userParameters, ["customerId": "2022"])
    }

    func testFailureKeepsPreviousConfig() async {
        let transport = MockTransport([.response(status: 200, body: cachedResponse), .response(status: 500, body: "")])
        let core = env.makeCore(transport: transport)
        await core.loadConfiguration()

        let source = await core.loadConfiguration(forceRefresh: true)
        XCTAssertEqual(source, .none)
        XCTAssertEqual(core.engine.config.surveys.count, 1)
    }

    func testLookUpParametersFromStorage() {
        let core = env.makeCore()
        env.appStore.set("123", forKey: "userID")
        XCTAssertEqual(core.lookUpParameters(["userID", "rank"]), ["userID": "123"], "missing keys are skipped")
    }
}
