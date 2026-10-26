import Foundation

/// Which links load inside the survey and which open outside (Android: `WebViewConfigurator`).
/// Redirects between web pages are always followed (Android v2.0.15 lesson: no domain filter).
enum SurveyLinkPolicy {
    enum Decision: Equatable {
        case load
        case openExternally
    }

    private static let inlineSchemes: Set<String> = ["http", "https", "about", "data", "blob", "javascript"]
    private static let appStoreHosts: Set<String> = ["apps.apple.com", "itunes.apple.com"]

    static func decision(for url: URL) -> Decision {
        guard let scheme = url.scheme?.lowercased() else { return .load }
        if inlineSchemes.contains(scheme) {
            if let host = url.host?.lowercased(), appStoreHosts.contains(host) { return .openExternally }
            return .load
        }
        // mailto:, tel:, sms:, itms-apps:, other apps' URL schemes
        return .openExternally
    }
}
