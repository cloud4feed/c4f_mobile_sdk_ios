import Foundation

/// Central constants. Update `sdkVersion` when releasing a new version.
public enum SDKConstants {
    // ===== SDK VERSION =====
    public static let sdkVersion = "1.0.1"
    public static let sdkName = "MobileSDK-iOS"

    // ===== API CONFIGURATION =====
    static let configEndpoint = URL(string: "https://anonym.cloud4feed.com/api/anonym/get-mobilesdk-surveys")!
    static let apiTimeout: TimeInterval = 10
    static let apiMaxRetries = 2
    public static let cacheDurationHours: Int64 = 24

    // ===== DEFAULTS (same as Android) =====
    static let defaultTriggerType = "instant"
    static let defaultModalStyle = "full_screen"
    static let defaultAnimation = "slide_up"
    static let defaultBackgroundColor = "#FFFFFF"
    static let defaultPriority = 1

    // ===== BUTTON DETECTION =====
    /// Buttons with one of these identifiers open the "generic" button survey
    /// (a button survey without its own `buttonTriggerId`).
    public static let predefinedButtonIds = ["survey_button", "take_survey", "feedback_button", "rate_app"]

    // ===== STORAGE =====
    /// UserDefaults suite written by `setUserProperty` (Android: `survey_sdk_data`).
    static let dataSuiteName = "com.cloud4feed.mobilesdk.data"
    /// UserDefaults suite for session metrics (Android: `survey_sdk_session`).
    static let sessionSuiteName = "com.cloud4feed.mobilesdk.session"
    /// UserDefaults suite for "trigger once" memory (Android: `survey_sdk_trigger_once`).
    static let triggerOnceSuiteName = "com.cloud4feed.mobilesdk.triggeronce"
    /// UserDefaults suite for pending app-exit surveys (Android: survey_sdk_exit).
    static let exitSuiteName = "com.cloud4feed.mobilesdk.exit"

    // ===== LOGGING =====
    static let logSubsystem = "com.cloud4feed.mobilesdk"
}
