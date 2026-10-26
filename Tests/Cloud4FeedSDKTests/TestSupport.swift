import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Cloud4FeedSDK

/// Mutable clock for deterministic tests.
final class TestClock {
    var date: Date
    init(_ date: Date = Date(timeIntervalSince1970: 1_760_000_000)) { self.date = date }
    func now() -> Date { date }
    func advance(seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

/// Device values for tests.
final class StubDevice: DeviceInfoProviding {
    var values: [String: String]
    init(_ values: [String: String] = [:]) { self.values = values }
    func value(forKey key: String) -> String? { values[key] }
    func deviceInfo() -> [(key: String, value: String)] {
        values.keys.sorted().filter { !["latitude", "longitude"].contains($0) }.map { (key: $0, value: values[$0]!) }
    }
    func locationInfo() -> [(key: String, value: String)] {
        ["latitude", "longitude"].compactMap { key in values[key].map { (key: key, value: $0) } }
    }
}

/// Transport that replays queued responses and records requests.
final class MockTransport: HTTPTransport {
    enum Reply {
        case response(status: Int, body: String)
        case failure(Error)
    }

    var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
        switch replies.removeFirst() {
        case .failure(let error):
            throw error
        case .response(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }
}

struct TestEnvironment {
    let clock = TestClock()
    let dataStore = InMemoryStore()
    let appStore = InMemoryStore()
    let sessionStore = InMemoryStore()
    let triggerOnceStore = InMemoryStore()
    let device: StubDevice
    let cacheDirectory: URL
    var installDate: Date?

    init(device: [String: String] = [:], installDate: Date? = nil) {
        self.device = StubDevice(device)
        self.installDate = installDate
        self.cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("c4f-tests-\(UUID().uuidString)", isDirectory: true)
    }

    func makeCore(parameters: [String: String] = [:], transport: HTTPTransport = MockTransport([])) -> SDKCore {
        let install = installDate
        let clock = self.clock
        return SDKCore(apiKey: "sk_test",
                       parameters: parameters,
                       dataStore: dataStore,
                       sessionStore: sessionStore,
                       triggerOnceStore: triggerOnceStore,
                       appStores: [appStore],
                       device: device,
                       installDate: { install },
                       transport: transport,
                       cacheDirectory: cacheDirectory,
                       retryDelay: 0,
                       now: clock.now)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

func survey(_ id: String = "1", configure: (inout SurveyConfig) -> Void = { _ in }) -> SurveyConfig {
    var survey = SurveyConfig()
    survey.surveyId = id
    survey.baseUrl = "https://cx.cloud4feed.com/?c=code\(id)"
    configure(&survey)
    return survey
}

enum Fixtures {
    /// Shape of a real `get-mobilesdk-surveys` response.
    static let response = """
    {
      "success": true,
      "messages": [],
      "data": {
        "sdkVersion": "2.0.18",
        "cacheDurationHours": 0,
        "surveys": [
          {
            "surveyId": "180",
            "surveyName": "Lacoste",
            "baseUrl": "https://cx.cloud4feed.com/?c=5qZu-abc",
            "status": true,
            "enableButtonTrigger": true,
            "buttonTriggerId": "checkout_button",
            "enableNavigationTrigger": true,
            "triggerScreens": ["home", null, "cart"],
            "triggerTabs": ["womens"],
            "timeDelay": "1500",
            "scrollThreshold": 800,
            "triggerType": "delayed",
            "modalStyle": "bottom_sheet",
            "animationType": "fade",
            "backgroundColor": "#000000",
            "probability": 0.5,
            "maxShowsPerSession": 2,
            "cooldownPeriod": 60000,
            "triggerOnce": "true",
            "priority": "3",
            "collectDeviceId": false,
            "customParams": [
              { "name": "param_1", "source": "storage", "key": "customerId" },
              { "name": "param_2", "source": "SESSION", "key": "current_screen" },
              { "name": "broken", "source": "NOPE" },
              { "source": "DEVICE" }
            ],
            "exclusionRules": [
              { "name": "tier", "source": "STORAGE", "key": "user_tier", "ruleOperator": 14, "matchValue": "gold" },
              { "name": "os", "source": "DEVICE", "key": "osVersion", "operator": "NOT_EQUALS", "matchValue": "17" },
              { "name": "str", "source": "SESSION", "ruleOperator": "9", "matchValue": "x" },
              { "name": "backend", "source": "STORAGE", "ruleOperator": "StartWith", "matchValue": "a" },
              { "name": "bad", "source": "WHATEVER", "ruleOperator": 14 }
            ]
          },
          {
            "baseUrl": "https://cx.cloud4feed.com/?c=other",
            "priority": 2
          },
          "not-an-object"
        ]
      }
    }
    """
}
