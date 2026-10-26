import Foundation

// Configuration model. Field names and defaults match the Android SDK (`MobileSDK.kt`) and the
// backend payload of `get-mobilesdk-surveys`, so one Configuration Manager setup drives both platforms.

public struct Config: Equatable {
    public var sdkVersion: String
    public var cacheDurationHours: Int64
    public var surveys: [SurveyConfig]

    public init(sdkVersion: String = SDKConstants.sdkVersion,
                cacheDurationHours: Int64 = SDKConstants.cacheDurationHours,
                surveys: [SurveyConfig] = []) {
        self.sdkVersion = sdkVersion
        self.cacheDurationHours = cacheDurationHours
        self.surveys = surveys
    }

    /// Used when there is no usable configuration (Android: `DefaultConfig.EMPTY_CONFIG`).
    public static let empty = Config()
}

public struct SurveyConfig: Equatable {
    // Identity
    public var surveyId: String = ""
    public var surveyName: String = ""
    public var baseUrl: String = ""
    public var status: Bool = true

    // Trigger switches
    public var enableButtonTrigger: Bool = false
    public var enableScrollTrigger: Bool = false
    public var enableNavigationTrigger: Bool = false
    public var enableAppLaunchTrigger: Bool = false
    public var enableExitTrigger: Bool = false
    public var enableTabChangeTrigger: Bool = false

    /// Custom button id. Nil = "generic" button survey opened by the predefined ids.
    public var buttonTriggerId: String?

    // Trigger configuration
    public var triggerScreens: Set<String> = []
    public var triggerTabs: Set<String> = []
    /// Milliseconds, used when `triggerType == "delayed"`.
    public var timeDelay: Int64 = 0
    /// Pixels (iOS: content offset in points x screen scale).
    public var scrollThreshold: Int = 0
    public var triggerType: String = SDKConstants.defaultTriggerType

    // Display
    public var modalStyle: String = SDKConstants.defaultModalStyle
    public var animationType: String = SDKConstants.defaultAnimation
    public var backgroundColor: String = SDKConstants.defaultBackgroundColor

    // Targeting and limits
    public var exclusionRules: [ExclusionRule] = []
    /// Read but not applied (same as Android; kept for backend compatibility).
    public var probability: Double = 1.0
    /// 0 = unlimited.
    public var maxShowsPerSession: Int = 0
    /// Milliseconds between two displays of the same survey. 0 = no cooldown.
    public var cooldownPeriod: Int64 = 0
    public var triggerOnce: Bool = false
    public var priority: Int = SDKConstants.defaultPriority

    // Data collection
    public var collectDeviceId: Bool = false
    public var collectDeviceModel: Bool = false
    public var collectLocation: Bool = false
    public var collectAppUsage: Bool = false
    public var customParams: [CustomParam] = []

    public init() {}
}

/// Where a custom parameter or an exclusion rule reads its value from.
public enum ValueSource: String, CaseIterable, Equatable {
    case storage = "STORAGE"
    case device = "DEVICE"
    case url = "URL"
    case timestamp = "TIMESTAMP"
    case session = "SESSION"
    case installTime = "INSTALL_TIME"
    case appUsage = "APP_USAGE"
}

/// A value appended to the survey URL as `&name=value`.
/// `name` is the URL key, `key` says which value to read from `source` (defaults to `name`).
public struct CustomParam: Equatable {
    public var name: String
    public var source: ValueSource
    public var key: String?

    public init(name: String, source: ValueSource, key: String? = nil) {
        self.name = name
        self.source = source
        self.key = key
    }
}

/// On-device rule: when it matches, the survey is not shown to this user.
public struct ExclusionRule: Equatable {
    public var name: String
    public var source: ValueSource
    public var key: String?
    public var value: String?
    public var ruleOperator: ExclusionOperator
    public var matchValue: String
    public var caseSensitive: Bool

    public init(name: String,
                source: ValueSource,
                key: String? = nil,
                value: String? = nil,
                ruleOperator: ExclusionOperator = .equals,
                matchValue: String = "",
                caseSensitive: Bool = false) {
        self.name = name
        self.source = source
        self.key = key
        self.value = value
        self.ruleOperator = ruleOperator
        self.matchValue = matchValue
        self.caseSensitive = caseSensitive
    }
}

/// Operator ids are the backend / Configuration Manager ids.
public enum ExclusionOperator: Int, CaseIterable, Equatable {
    case lessThan = 1
    case lessOrEqual = 2
    case `in` = 3
    case notIn = 4
    case greaterThan = 5
    case greaterOrEqual = 6
    case empty = 7
    case notEmpty = 8
    case contains = 9
    case notContains = 10
    case startsWith = 11
    case endsWith = 12
    case length = 13
    case equals = 14
    case notEquals = 15

    /// Unknown ids fall back to EQUALS (same as Android).
    static func from(id: Int) -> ExclusionOperator {
        ExclusionOperator(rawValue: id) ?? .equals
    }

    /// Android enum names (`NOT_EQUALS`) plus the backend spellings (`NotEqual`, `StartWith`,
    /// `LastWith`, `Lenghth`, `EqualTo`). Case-insensitive; underscores are ignored.
    static func from(name: String) -> ExclusionOperator? {
        let normalized = name.uppercased().replacingOccurrences(of: "_", with: "")
        switch normalized {
        case "LESSTHAN": return .lessThan
        case "LESSOREQUAL": return .lessOrEqual
        case "IN": return .`in`
        case "NOTIN": return .notIn
        case "GREATERTHAN": return .greaterThan
        case "GREATEROREQUAL": return .greaterOrEqual
        case "EMPTY": return .empty
        case "NOTEMPTY": return .notEmpty
        case "CONTAINS": return .contains
        case "NOTCONTAINS": return .notContains
        case "STARTSWITH", "STARTWITH": return .startsWith
        case "ENDSWITH", "LASTWITH": return .endsWith
        case "LENGTH", "LENGHTH": return .length
        case "EQUALS", "EQUALTO": return .equals
        case "NOTEQUALS", "NOTEQUAL": return .notEquals
        default: return nil
        }
    }
}
