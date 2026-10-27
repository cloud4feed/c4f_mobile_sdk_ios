import Foundation

/// URL source: query parameters of the last deep link the app handed to the SDK
/// (`MobileSDK.handle(url:)`). Android reads them from the opening Activity's Intent.
final class URLParameterStore {
    private(set) var parameters: [String: String] = [:]

    func update(from url: URL) {
        var values: [String: String] = [:]
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for item in items where values[item.name] == nil {
            // First occurrence wins (same as Uri.getQueryParameter).
            values[item.name] = item.value ?? ""
        }
        parameters = values
        SDKLog.debug("URL parameters updated: \(values.keys.sorted())")
    }

    func value(forKey key: String) -> String? {
        parameters[key]
    }

    func clear() {
        parameters.removeAll()
    }
}
