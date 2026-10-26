import XCTest
@testable import Cloud4FeedSDK

final class ValueResolverTests: XCTestCase {
    override func setUp() { SDKLog.isEnabled = false }

    func testStorageOrderAndTypes() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let core = env.makeCore()

        env.appStore.set("from_app", forKey: "customerId")
        XCTAssertEqual(core.resolver.value(source: .storage, key: "customerId", name: "p"), "from_app")

        core.setUserProperty("1011", forKey: "customerId")
        XCTAssertEqual(core.resolver.value(source: .storage, key: "customerId", name: "p"), "1011",
                       "SDK's own store (setUserProperty) is read first")

        env.appStore.set(true, forKey: "is_premium")
        env.appStore.set(3, forKey: "cart_items")
        env.appStore.set(4.5, forKey: "rating")
        env.appStore.set(Data(), forKey: "blob")
        XCTAssertEqual(core.resolver.value(source: .storage, key: "is_premium", name: "p"), "true")
        XCTAssertEqual(core.resolver.value(source: .storage, key: "cart_items", name: "p"), "3")
        XCTAssertEqual(core.resolver.value(source: .storage, key: "rating", name: "p"), "4.5")
        XCTAssertNil(core.resolver.value(source: .storage, key: "blob", name: "p"), "unsupported types give no value")
        XCTAssertNil(core.resolver.value(source: .storage, key: "nothing", name: "p"))
    }

    func testDefaultLookupKeys() {
        XCTAssertEqual(ValueResolver.lookupKey(source: .storage, key: nil, name: "userID"), "userID")
        XCTAssertEqual(ValueResolver.lookupKey(source: .timestamp, key: nil, name: "x"), "millis")
        XCTAssertEqual(ValueResolver.lookupKey(source: .installTime, key: nil, name: "x"), "days")
        XCTAssertEqual(ValueResolver.lookupKey(source: .appUsage, key: nil, name: "x"), "sessions")
        XCTAssertEqual(ValueResolver.lookupKey(source: .device, key: "osVersion", name: "x"), "osVersion")
    }

    func testTimestampFormats() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        // 2025-10-05 13:07:09 UTC, a Sunday.
        env.clock.date = Date(timeIntervalSince1970: 1_759_669_629.5)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let core = env.makeCore()
        let resolver = ValueResolver(storage: core.storage, device: env.device, session: core.session,
                                     urlParameters: core.urlParameters, installDate: { nil },
                                     now: env.clock.now, calendar: calendar)

        XCTAssertEqual(resolver.timestampValue("millis"), "1759669629500")
        XCTAssertEqual(resolver.timestampValue("timestamp"), "1759669629500")
        XCTAssertEqual(resolver.timestampValue("current_time"), "1759669629500")
        XCTAssertEqual(resolver.timestampValue("unknown"), "1759669629500")
        XCTAssertEqual(resolver.timestampValue("seconds"), "1759669629")
        XCTAssertEqual(resolver.timestampValue("iso"), "2025-10-05 13:07")
        XCTAssertEqual(resolver.timestampValue("hour"), "13")
        XCTAssertEqual(resolver.timestampValue("day_of_week"), "1", "1 = Sunday, as on Android")
        XCTAssertEqual(resolver.timestampValue("day_of_month"), "5")
        XCTAssertEqual(resolver.timestampValue("month"), "10")
    }

    func testInstallTime() {
        var env = TestEnvironment()
        env.installDate = env.clock.date.addingTimeInterval(-(3 * 86_400 + 5 * 3_600))
        defer { env.cleanUp() }
        let core = env.makeCore()

        XCTAssertEqual(core.resolver.value(source: .installTime, key: nil, name: "x"), "3")
        XCTAssertEqual(core.resolver.value(source: .installTime, key: "hours", name: "x"), "77")
        XCTAssertEqual(core.resolver.value(source: .installTime, key: "minutes", name: "x"), "4620")
        let installMillis = String(Int64(env.installDate!.timeIntervalSince1970 * 1000))
        XCTAssertEqual(core.resolver.value(source: .installTime, key: "install_timestamp", name: "x"), installMillis)

        let unknown = TestEnvironment()
        defer { unknown.cleanUp() }
        XCTAssertNil(unknown.makeCore().resolver.value(source: .installTime, key: nil, name: "x"))
    }

    func testSessionAndAppUsage() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let core = env.makeCore()
        let session = core.session

        XCTAssertEqual(session.sessionValue(forKey: "first_launch"), "true")
        session.trackSessionStart()
        session.trackSessionStart() // once per process
        XCTAssertEqual(session.sessionValue(forKey: "session_count"), "1")
        XCTAssertEqual(session.sessionValue(forKey: "first_launch"), "true")
        XCTAssertNil(session.appUsageValue("last_session"), "no previous session yet")

        env.clock.advance(seconds: 150)
        XCTAssertEqual(session.sessionValue(forKey: "session_duration"), "150")
        XCTAssertEqual(session.sessionValue(forKey: "session_duration_minutes"), "2")

        session.trackScreenView()
        session.trackScreenView()
        XCTAssertEqual(session.sessionValue(forKey: "screens_count"), "2")
        XCTAssertEqual(session.appUsageValue("screen_views"), "2")

        // A new process: a second session starts 10 minutes after the first one.
        env.clock.advance(seconds: 450)
        let nextProcess = SessionTracker(store: env.sessionStore, now: env.clock.now)
        nextProcess.trackSessionStart()
        XCTAssertEqual(nextProcess.appUsageValue("sessions"), "2")
        XCTAssertEqual(nextProcess.sessionValue(forKey: "first_launch"), "false")
        XCTAssertEqual(nextProcess.appUsageValue("last_session"), "10")

        nextProcess.setSessionData("custom", forKey: "session_count")
        XCTAssertEqual(nextProcess.sessionValue(forKey: "session_count"), "custom", "setSessionData wins")
        XCTAssertNil(nextProcess.appUsageValue("app_usage_time"))
    }

    func testCurrentScreen() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let core = env.makeCore()
        XCTAssertNil(core.resolver.value(source: .session, key: "current_screen", name: "x"))
        core.session.currentScreen = "home"
        XCTAssertEqual(core.resolver.value(source: .session, key: "current_screen", name: "x"), "home")
        XCTAssertEqual(core.resolver.value(source: .session, key: "currentScreen", name: "x"), "home")
    }

    func testURLParameters() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let core = env.makeCore()
        core.urlParameters.update(from: URL(string: "surveytest://open?campaign=summer&campaign=other&empty=")!)
        XCTAssertEqual(core.resolver.value(source: .url, key: "campaign", name: "x"), "summer", "first value wins")
        XCTAssertEqual(core.resolver.value(source: .url, key: "empty", name: "x"), "")
        XCTAssertNil(core.resolver.value(source: .url, key: "none", name: "x"))
    }

    func testDeviceUnknownIsNoValue() {
        let env = TestEnvironment(device: ["latitude": "unknown", "osVersion": "17.4"])
        defer { env.cleanUp() }
        let core = env.makeCore()
        XCTAssertNil(core.resolver.value(source: .device, key: "latitude", name: "x"))
        XCTAssertEqual(core.resolver.value(source: .device, key: "osVersion", name: "x"), "17.4")
    }

    func testFoundationDeviceInfo() {
        let device = FoundationDeviceInfo(locale: Locale(identifier: "tr_TR"),
                                          timeZone: TimeZone(identifier: "Europe/Istanbul")!)
        XCTAssertEqual(device.value(forKey: "platform"), "iOS")
        XCTAssertEqual(device.value(forKey: "manufacturer"), "Apple")
        XCTAssertEqual(device.value(forKey: "locale"), "tr_TR")
        XCTAssertEqual(device.value(forKey: "country"), "TR")
        XCTAssertEqual(device.value(forKey: "COUNTRY"), "TR", "case-insensitive fallback")
        XCTAssertEqual(device.value(forKey: "timezone"), "Europe/Istanbul")
        XCTAssertEqual(device.value(forKey: "is_encrypted"), "encrypted")
        XCTAssertNotNil(device.value(forKey: "osVersion"))
        XCTAssertNil(device.value(forKey: "is_roaming"), "not available on iOS")
    }
}
