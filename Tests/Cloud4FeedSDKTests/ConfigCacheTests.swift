import XCTest
@testable import Cloud4FeedSDK

final class ConfigCacheTests: XCTestCase {
    private var env: TestEnvironment!

    override func setUp() {
        SDKLog.isEnabled = false
        env = TestEnvironment()
    }

    override func tearDown() { env.cleanUp() }

    private func makeCache() -> ConfigCache {
        ConfigCache(directory: env.cacheDirectory, now: env.clock.now)
    }

    private func sampleConfig(hours: Int64) -> Config {
        Config(sdkVersion: "2.0.18", cacheDurationHours: hours, surveys: [
            survey("1") {
                $0.triggerScreens = ["home"]
                $0.customParams = [CustomParam(name: "p", source: .storage, key: "k")]
                $0.exclusionRules = [ExclusionRule(name: "r", source: .device, key: "osVersion", ruleOperator: .notIn, matchValue: "16,17")]
            },
        ])
    }

    func testRoundTripWithinDuration() {
        let cache = makeCache()
        let config = sampleConfig(hours: 24)
        cache.save(config, parameters: ["customerId": "1011"])

        env.clock.advance(seconds: 23 * 3600)
        XCTAssertEqual(cache.load(parameters: ["customerId": "1011"]), config)
    }

    func testExpires() {
        let cache = makeCache()
        cache.save(sampleConfig(hours: 1), parameters: [:])
        env.clock.advance(seconds: 3601)
        XCTAssertNil(cache.load(parameters: [:]))
        env.clock.advance(seconds: -3601)
        XCTAssertNil(cache.load(parameters: [:]), "an expired cache is deleted")
    }

    func testZeroDurationIsNeverReused() {
        let cache = makeCache()
        cache.save(sampleConfig(hours: 0), parameters: [:])
        XCTAssertNil(cache.load(parameters: [:]))
    }

    func testOtherParametersMiss() {
        let cache = makeCache()
        cache.save(sampleConfig(hours: 24), parameters: ["customerId": "1011"])
        XCTAssertNil(cache.load(parameters: ["customerId": "2022"]))
    }

    func testCorruptOrOldFormatIsDiscarded() throws {
        let cache = makeCache()
        try FileManager.default.createDirectory(at: env.cacheDirectory, withIntermediateDirectories: true)
        let file = env.cacheDirectory.appendingPathComponent(ConfigCache.fileName)

        try Data("garbage".utf8).write(to: file)
        XCTAssertNil(cache.load(parameters: [:]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        try Data(#"{"formatVersion": 0, "config": {"surveys": []}}"#.utf8).write(to: file)
        XCTAssertNil(cache.load(parameters: [:]))
    }

    func testClear() {
        let cache = makeCache()
        cache.save(sampleConfig(hours: 24), parameters: [:])
        cache.clear()
        XCTAssertNil(cache.load(parameters: [:]))
    }
}
