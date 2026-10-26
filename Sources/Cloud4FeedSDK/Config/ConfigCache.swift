import Foundation

/// On-disk cache of the last configuration (Android: `ConfigCacheManager`).
///
/// A cached config is used only when all of these hold:
/// - it was written by the current cache format,
/// - it was fetched with the same user parameters (`initialize` parameters),
/// - it is younger than `cacheDurationHours` (0 = never reuse, always fetch fresh).
///
/// The file lives in the app's Caches directory: the system may purge it, which only means one
/// extra network request.
final class ConfigCache {
    /// Bump whenever the cached layout changes; older files are discarded instead of half-read.
    static let formatVersion = 1
    static let fileName = "config_cache.json"

    private let fileURL: URL
    private let fileManager: FileManager
    private let now: () -> Date

    init(directory: URL? = nil, fileManager: FileManager = .default, now: @escaping () -> Date = Date.init) {
        let baseDirectory = directory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Cloud4FeedSDK", isDirectory: true)
            ?? fileManager.temporaryDirectory.appendingPathComponent("Cloud4FeedSDK", isDirectory: true)
        self.fileURL = baseDirectory.appendingPathComponent(ConfigCache.fileName)
        self.fileManager = fileManager
        self.now = now
    }

    func save(_ config: Config, parameters: [String: String]) {
        let envelope: JSONValue = .object([
            "formatVersion": .number(Double(ConfigCache.formatVersion)),
            "savedAtMillis": .number(Self.millis(now())),
            "cacheDurationHours": .number(Double(config.cacheDurationHours)),
            "paramsHash": .string(StableHash.parameters(parameters)),
            "config": ConfigParser.encode(config),
        ])
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try envelope.serialized().write(to: fileURL, options: .atomic)
            SDKLog.debug("Configuration cached (\(config.surveys.count) surveys)", .cache)
        } catch {
            SDKLog.error("Failed to cache configuration: \(error)", .cache)
        }
    }

    func load(parameters: [String: String]) -> Config? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let envelope = try JSONValue.parse(Data(contentsOf: fileURL))

            guard envelope["formatVersion"]?.intValue == ConfigCache.formatVersion else {
                SDKLog.debug("Cache format changed, discarding old cache", .cache)
                clear()
                return nil
            }

            guard envelope["paramsHash"]?.stringValue == StableHash.parameters(parameters) else {
                SDKLog.debug("Cached config was fetched with other parameters, discarding", .cache)
                clear()
                return nil
            }

            let savedAt = envelope["savedAtMillis"]?.doubleValue ?? 0
            let hours = envelope["cacheDurationHours"]?.doubleValue ?? Double(SDKConstants.cacheDurationHours)
            let age = Self.millis(now()) - savedAt
            if hours <= 0 || age > hours * 3_600_000 {
                SDKLog.debug("Cache expired, age: \(Int(age / 60_000)) minutes", .cache)
                clear()
                return nil
            }

            guard let configObject = envelope["config"]?.objectValue,
                  let config = ConfigParser.parseConfigObject(configObject) else {
                SDKLog.warning("Cached config unreadable, discarding", .cache)
                clear()
                return nil
            }

            // A survey that failed to parse means the cache is not trustworthy: fetch fresh instead.
            let expected = configObject["surveys"]?.arrayValue?.count ?? 0
            guard config.surveys.count == expected else {
                SDKLog.warning("Cached config parsed \(config.surveys.count)/\(expected) surveys, discarding", .cache)
                clear()
                return nil
            }

            SDKLog.debug("Using cached configuration", .cache)
            return config
        } catch {
            SDKLog.error("Failed to load cached configuration: \(error)", .cache)
            clear()
            return nil
        }
    }

    func clear() {
        try? fileManager.removeItem(at: fileURL)
    }

    private static func millis(_ date: Date) -> Double {
        (date.timeIntervalSince1970 * 1000).rounded()
    }
}
