import Foundation

/// Supplies DEVICE source values. Key names match the Android SDK (`DeviceUtils`), e.g.
/// `deviceID`, `deviceModel`, `platform`, `osVersion`, `locale`, `battery_level`, `is_wifi`.
/// A nil result means "no value": the custom parameter is skipped / the rule sees an empty value.
protocol DeviceInfoProviding: AnyObject {
    func value(forKey key: String) -> String?
    /// Values appended to the survey URL when `collectDeviceId` / `collectDeviceModel` is on
    /// (Android: `DeviceUtils.getDeviceInfo`).
    func deviceInfo() -> [(key: String, value: String)]
    /// Values appended when `collectLocation` is on. Empty without location permission.
    func locationInfo() -> [(key: String, value: String)]
}

/// Foundation-only device values. The iOS layer (Phase 2) adds UIKit / Network / CoreLocation
/// values on top of these through `extraValues`.
class FoundationDeviceInfo: DeviceInfoProviding {
    let locale: Locale
    let timeZone: TimeZone
    let bundle: Bundle
    let processInfo: ProcessInfo

    init(locale: Locale = .current,
         timeZone: TimeZone = .current,
         bundle: Bundle = .main,
         processInfo: ProcessInfo = .processInfo) {
        self.locale = locale
        self.timeZone = timeZone
        self.bundle = bundle
        self.processInfo = processInfo
    }

    /// Platform-specific values (override in the iOS layer).
    func extraValues() -> [String: String] { [:] }

    func baseValues() -> [String: String] {
        let os = processInfo.operatingSystemVersion
        var osVersion = "\(os.majorVersion).\(os.minorVersion)"
        if os.patchVersion > 0 { osVersion += ".\(os.patchVersion)" }

        var values: [String: String] = [
            "platform": "iOS",
            "manufacturer": "Apple",
            "brand": "Apple",
            "osVersion": osVersion,
            // Android sends the API level here; on iOS this is the major OS version.
            "sdkVersion": String(os.majorVersion),
            "locale": Self.localeIdentifier(locale),
            "timezone": timeZone.identifier,
            // iOS devices are always encrypted. Android reports "encrypted" too.
            "is_encrypted": "encrypted",
        ]
        if let country = Self.regionCode(locale), !country.isEmpty {
            values["country"] = country
        }
        if let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            values["appVersion"] = appVersion
        }
        return values
    }

    func allValues() -> [String: String] {
        baseValues().merging(extraValues()) { _, extra in extra }
    }

    func value(forKey key: String) -> String? {
        let values = allValues()
        if let value = values[key] { return value }
        // Android matches the extra keys case-insensitively; do it for every key.
        let lowered = key.lowercased()
        if lowered == "screensize" { return values["screenResolution"] }
        return values.first { $0.key.lowercased() == lowered }?.value
    }

    func deviceInfo() -> [(key: String, value: String)] {
        let keys = ["deviceID", "deviceModel", "platform", "osVersion", "manufacturer", "brand",
                    "sdkVersion", "screenResolution", "networkType", "timezone", "locale",
                    "appVersion", "deviceOrientation"]
        let values = allValues()
        return keys.compactMap { key in values[key].map { (key: key, value: $0) } }
    }

    func locationInfo() -> [(key: String, value: String)] {
        let values = allValues()
        return ["latitude", "longitude", "location_accuracy"].compactMap { key in
            values[key].map { (key: key, value: $0) }
        }
    }

    /// Android format: `en_US`.
    static func localeIdentifier(_ locale: Locale) -> String {
        let language = locale.languageCode ?? "und"
        if let region = regionCode(locale), !region.isEmpty {
            return "\(language)_\(region)"
        }
        return language
    }

    static func regionCode(_ locale: Locale) -> String? {
        locale.regionCode
    }
}
