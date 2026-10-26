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
    let exitStore = InMemoryStore()
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
                       exitStore: exitStore,
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

/// Scheduler driven by the test clock: `advance(seconds:)` runs the work that became due.
final class ManualScheduler: Scheduling {
    final class Item: Cancellable {
        let due: Date
        let order: Int
        let work: () -> Void
        var isCancelled = false
        init(due: Date, order: Int, work: @escaping () -> Void) {
            self.due = due
            self.order = order
            self.work = work
        }
        func cancel() { isCancelled = true }
    }

    private let clock: TestClock
    private var items: [Item] = []
    private var counter = 0

    init(clock: TestClock) { self.clock = clock }

    var pendingCount: Int { items.filter { !$0.isCancelled }.count }

    @discardableResult
    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> Cancellable {
        counter += 1
        let item = Item(due: clock.date.addingTimeInterval(max(0, delay)), order: counter, work: work)
        items.append(item)
        return item
    }

    /// Moves the clock forward, running due work in time order (work may schedule more work).
    func advance(seconds: TimeInterval) {
        let end = clock.date.addingTimeInterval(seconds)
        while let next = items.filter({ !$0.isCancelled && $0.due <= end })
                .min(by: { ($0.due, $0.order) < ($1.due, $1.order) }) {
            items.removeAll { $0 === next }
            if next.due > clock.date { clock.date = next.due }
            next.work()
        }
        clock.date = end
        items.removeAll { $0.isCancelled }
    }
}

/// Records presented surveys; the test closes them with `closeCurrent()`.
final class FakePresenter: SurveyPresenting {
    private(set) var presented: [SurveyPresentationRequest] = []
    private var closeHandler: (() -> Void)?
    var canPresent = true

    var presentedIds: [String] { presented.map(\.surveyId) }

    func present(_ request: SurveyPresentationRequest, onClose: @escaping () -> Void) -> Bool {
        guard canPresent else { return false }
        presented.append(request)
        closeHandler = onClose
        return true
    }

    func closeCurrent() {
        let handler = closeHandler
        closeHandler = nil
        handler?()
    }
}

/// Integration stub that records what the facade asked for.
final class RecordingIntegration: PlatformIntegration {
    private(set) var startedHybrid: Bool?
    private(set) var startedAutoScreens: Bool?
    private(set) var configurationAppliedCount = 0
    private(set) var manualScreens = 0
    private(set) var stopped = false

    func start(hybridMode: Bool, automaticScreenTracking: Bool) {
        startedHybrid = hybridMode
        startedAutoScreens = automaticScreenTracking
    }
    func configurationApplied() { configurationAppliedCount += 1 }
    func screenTrackedManually() { manualScreens += 1 }
    func stop() { stopped = true }
}

extension TestEnvironment {
    /// Coordinator over a core whose engine already has `surveys` applied.
    func makeCoordinator(_ surveys: [SurveyConfig]? = nil,
                         parameters: [String: String] = [:]) -> (SDKCore, TriggerCoordinator, FakePresenter, ManualScheduler) {
        let core = makeCore(parameters: parameters)
        let presenter = FakePresenter()
        let scheduler = ManualScheduler(clock: clock)
        let coordinator = TriggerCoordinator(core: core, presenter: presenter, scheduler: scheduler, now: clock.now)
        if let surveys = surveys {
            core.engine.apply(Config(surveys: surveys))
        }
        return (core, coordinator, presenter, scheduler)
    }
}
