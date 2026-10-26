import Foundation
#if canImport(os)
import os
#endif

/// Logging. On Apple platforms it uses `os.Logger` (subsystem `com.cloud4feed.mobilesdk`), so the
/// output can be followed with:
///
///     xcrun simctl spawn booted log stream --predicate 'subsystem == "com.cloud4feed.mobilesdk"'
///
/// Elsewhere (Linux/Windows unit tests) it prints to stdout.
enum SDKLog {
    /// Set to false to silence the SDK (e.g. in unit tests).
    static var isEnabled = true

    enum Category: String {
        case sdk = "MobileSDK"
        case api = "SurveyApiService"
        case cache = "ConfigCache"
        case rules = "Rules"
        case webView = "WebView"
    }

    static func debug(_ message: @autoclosure () -> String, _ category: Category = .sdk) {
        write(message(), category, level: "D")
    }

    static func info(_ message: @autoclosure () -> String, _ category: Category = .sdk) {
        write(message(), category, level: "I")
    }

    static func warning(_ message: @autoclosure () -> String, _ category: Category = .sdk) {
        write(message(), category, level: "W")
    }

    static func error(_ message: @autoclosure () -> String, _ category: Category = .sdk) {
        write(message(), category, level: "E")
    }

    private static func write(_ message: String, _ category: Category, level: String) {
        guard isEnabled else { return }
        #if canImport(os)
        let logger = Logger(subsystem: SDKConstants.logSubsystem, category: category.rawValue)
        switch level {
        case "E": logger.error("\(message, privacy: .public)")
        case "W": logger.warning("\(message, privacy: .public)")
        case "I": logger.info("\(message, privacy: .public)")
        default: logger.debug("\(message, privacy: .public)")
        }
        #else
        print("[\(level)] \(category.rawValue): \(message)")
        #endif
    }
}
