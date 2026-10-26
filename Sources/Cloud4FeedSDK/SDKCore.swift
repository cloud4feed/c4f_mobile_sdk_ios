import Foundation

/// Where the applied configuration came from.
public enum ConfigSource: String {
    case cache = "CACHE"
    case network = "NETWORK"
    /// Neither cache nor network gave a configuration: no surveys until the next load.
    case none = "NONE"
}

/// Wires the platform-independent parts together. The public `MobileSDK` facade (Phase 2, UIKit)
/// owns one `SDKCore` and adds screen observation and survey presentation on top.
final class SDKCore {
    let apiKey: String
    private(set) var parameters: [String: String]

    let dataStore: KeyValueStore
    let storage: StorageReader
    let session: SessionTracker
    let urlParameters: URLParameterStore
    let device: DeviceInfoProviding
    let resolver: ValueResolver
    let eligibility: Eligibility
    let engine: SurveyEngine
    let cache: ConfigCache
    let service: ConfigService

    init(apiKey: String,
         parameters: [String: String] = [:],
         dataStore: KeyValueStore = UserDefaultsStore(suiteName: SDKConstants.dataSuiteName),
         sessionStore: KeyValueStore = UserDefaultsStore(suiteName: SDKConstants.sessionSuiteName),
         triggerOnceStore: KeyValueStore = UserDefaultsStore(suiteName: SDKConstants.triggerOnceSuiteName),
         appStores: [KeyValueStore] = [UserDefaultsStore(suiteName: nil)],
         device: DeviceInfoProviding = FoundationDeviceInfo(),
         installDate: @escaping () -> Date? = ValueResolver.appContainerCreationDate,
         transport: HTTPTransport = URLSessionTransport(),
         cacheDirectory: URL? = nil,
         retryDelay: TimeInterval = 1,
         now: @escaping () -> Date = Date.init) {
        // Build the graph with locals first; a class may not read `self` before every stored
        // property is set.
        let storage = StorageReader(stores: [dataStore] + appStores)
        let session = SessionTracker(store: sessionStore, now: now)
        let urlParameters = URLParameterStore()
        let resolver = ValueResolver(storage: storage,
                                     device: device,
                                     session: session,
                                     urlParameters: urlParameters,
                                     installDate: installDate,
                                     now: now)
        let eligibility = Eligibility(exclusion: ExclusionEvaluator(resolver: resolver),
                                      triggerOnce: TriggerOnceStore(store: triggerOnceStore),
                                      userParameters: parameters,
                                      now: now)

        self.apiKey = apiKey
        self.parameters = parameters
        self.dataStore = dataStore
        self.storage = storage
        self.session = session
        self.urlParameters = urlParameters
        self.device = device
        self.resolver = resolver
        self.eligibility = eligibility
        self.engine = SurveyEngine(eligibility: eligibility,
                                   session: session,
                                   collector: SurveyDataCollector(resolver: resolver))
        self.cache = ConfigCache(directory: cacheDirectory, now: now)
        self.service = ConfigService(apiKey: apiKey, transport: transport, retryDelay: retryDelay, now: now)
    }

    /// Values for `initialize(apiKey:lookupKeys:)`: keys are read from STORAGE; missing keys are skipped.
    func lookUpParameters(_ keys: [String]) -> [String: String] {
        var values: [String: String] = [:]
        for key in keys {
            if let value = storage.value(forKey: key) {
                values[key] = value
            } else {
                SDKLog.warning("'\(key)' not found in storage")
            }
        }
        return values
    }

    /// Replaces the user parameters. The next `loadConfiguration` uses them; a cache fetched with
    /// other parameters is not reused.
    func updateParameters(_ newParameters: [String: String]) {
        parameters = newParameters
        eligibility.userParameters = newParameters
    }

    /// Cache first (same parameters, not expired), otherwise network. A network config is cached.
    /// On failure the previous configuration stays applied.
    @discardableResult
    func loadConfiguration(forceRefresh: Bool = false) async -> ConfigSource {
        if !forceRefresh, let cached = cache.load(parameters: parameters) {
            engine.apply(cached)
            return .cache
        }
        do {
            let config = try await service.fetch(parameters: parameters)
            cache.save(config, parameters: parameters)
            engine.apply(config)
            return .network
        } catch {
            SDKLog.error("Configuration could not be loaded: \(error)")
            return .none
        }
    }

    // MARK: Data written by the app

    /// STORAGE value written through the SDK (Android: `setUserProperty` -> `survey_sdk_data`).
    func setUserProperty(_ value: String?, forKey key: String) {
        dataStore.set(value, forKey: key)
    }

    func setSessionData(_ value: String, forKey key: String) {
        session.setSessionData(value, forKey: key)
    }
}
