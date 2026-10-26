import Foundation

/// Builds the survey URL: `baseUrl` + `&name=value` pairs (Android: `buildSurveyUrl`).
///
/// Difference from Android: values are percent-encoded where a URL requires it (spaces, non-ASCII,
/// `&`, `=`, `#`, ...) because `URL` rejects them. Characters that are valid in a query
/// (`@`, `:`, `/`, `+`, ...) are kept as-is, so normal values produce the same URL as on Android,
/// where the WebView does the equivalent encoding while loading.
enum SurveyURLBuilder {
    /// Query-safe characters minus the ones that would break the `name=value&...` structure.
    static let allowedCharacters: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=#")
        return set
    }()

    static func build(baseUrl: String, parameters: [(name: String, value: String)]) -> String {
        guard !parameters.isEmpty else { return baseUrl }

        let query = parameters
            .map { "\(encode($0.name))=\(encode($0.value))" }
            .joined(separator: "&")

        let separator: String
        if baseUrl.hasSuffix("?") || baseUrl.hasSuffix("&") {
            separator = ""
        } else if baseUrl.contains("?") {
            separator = "&"
        } else {
            separator = "?"
        }
        return baseUrl + separator + query
    }

    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? text
    }
}

/// Collects the URL parameters of a survey (Android: `collectAllData` + `collectCustomParams`):
/// 1. custom parameters in configuration order; a parameter without a value is skipped
/// 2. device info when `collectDeviceId` / `collectDeviceModel` is on
/// 3. location when `collectLocation` is on (only if the app already has permission)
/// A later value for the same name replaces the earlier one but keeps its position.
struct SurveyDataCollector {
    let resolver: ValueResolver

    func parameters(for survey: SurveyConfig) -> [(name: String, value: String)] {
        var ordered = OrderedPairs()

        for param in survey.customParams {
            let value = resolver.value(source: param.source, key: param.key, name: param.name)
            if let value = value, !value.isEmpty {
                ordered.set(param.name, value)
                SDKLog.debug("Custom param added: \(param.name) = \(value)")
            } else {
                SDKLog.debug("Custom param skipped (no value): \(param.name)")
            }
        }

        if survey.collectDeviceId || survey.collectDeviceModel {
            for item in resolver.device.deviceInfo() { ordered.set(item.key, item.value) }
        }
        if survey.collectLocation {
            for item in resolver.device.locationInfo() { ordered.set(item.key, item.value) }
        }
        // collectAppUsage: Android only adds permission flags here (no usage data); nothing to add on iOS.

        return ordered.pairs
    }

    func surveyURL(for survey: SurveyConfig) -> String {
        let url = SurveyURLBuilder.build(baseUrl: survey.baseUrl, parameters: parameters(for: survey))
        SDKLog.debug("Survey URL: \(url)")
        return url
    }
}

/// Insertion-ordered name/value list with "replace in place" semantics (like a LinkedHashMap).
private struct OrderedPairs {
    private(set) var pairs: [(name: String, value: String)] = []
    private var index: [String: Int] = [:]

    mutating func set(_ name: String, _ value: String) {
        if let position = index[name] {
            pairs[position].value = value
        } else {
            index[name] = pairs.count
            pairs.append((name: name, value: value))
        }
    }
}
