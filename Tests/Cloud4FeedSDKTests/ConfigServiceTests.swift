import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Cloud4FeedSDK

final class ConfigServiceTests: XCTestCase {
    override func setUp() { SDKLog.isEnabled = false }

    private let clock = TestClock(Date(timeIntervalSince1970: 1_760_000_000.5))

    private func makeService(_ transport: MockTransport) -> ConfigService {
        ConfigService(apiKey: "sk_test", transport: transport, retryDelay: 0, now: clock.now)
    }

    func testRequestShape() throws {
        let request = try makeService(MockTransport([])).makeRequest(parameters: ["userID": "123", "rank": "chef"])

        XCTAssertEqual(request.url?.absoluteString, "https://anonym.cloud4feed.com/api/anonym/get-mobilesdk-surveys")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "MobileSDK-iOS/\(SDKConstants.sdkVersion)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")

        let body = try JSONDecoder().decode(ConfigRequestBody.self, from: try XCTUnwrap(request.httpBody))
        XCTAssertEqual(body.apiKey, "sk_test")
        XCTAssertEqual(body.timestamp, "1760000000500", "timestamp is a string of epoch millis")
        XCTAssertEqual(body.sdkVersion, SDKConstants.sdkVersion)
        XCTAssertEqual(body.sdkParams, [
            .init(paramName: "rank", paramValue: "chef"),
            .init(paramName: "userID", paramValue: "123"),
        ])

        // The backend expects "timestamp" as a JSON string, not a number.
        let raw = try JSONValue.parse(try XCTUnwrap(request.httpBody))
        XCTAssertEqual(raw["timestamp"], .string("1760000000500"))
    }

    func testSuccess() async throws {
        let transport = MockTransport([.response(status: 200, body: Fixtures.response)])
        let config = try await makeService(transport).fetch(parameters: [:])
        XCTAssertEqual(config.surveys.first?.surveyId, "180")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testRetriesNetworkErrorsAndServerErrors() async throws {
        let transport = MockTransport([
            .failure(URLError(.timedOut)),
            .response(status: 503, body: ""),
            .response(status: 200, body: Fixtures.response),
        ])
        let config = try await makeService(transport).fetch(parameters: [:])
        XCTAssertEqual(config.surveys.count, 2)
        XCTAssertEqual(transport.requests.count, 3, "1 attempt + 2 retries")
    }

    func testGivesUpAfterMaxRetries() async {
        let transport = MockTransport([
            .failure(URLError(.timedOut)), .failure(URLError(.timedOut)), .failure(URLError(.timedOut)),
            .response(status: 200, body: Fixtures.response),
        ])
        do {
            _ = try await makeService(transport).fetch(parameters: [:])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(transport.requests.count, 3)
        }
    }

    func testClientErrorIsNotRetried() async {
        let transport = MockTransport([.response(status: 401, body: "unauthorized"), .response(status: 200, body: Fixtures.response)])
        do {
            _ = try await makeService(transport).fetch(parameters: [:])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ConfigServiceError, .http(statusCode: 401))
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
}
