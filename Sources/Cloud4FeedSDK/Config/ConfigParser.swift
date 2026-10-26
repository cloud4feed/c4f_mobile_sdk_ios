import Foundation

/// Tolerant parser for the `get-mobilesdk-surveys` response and for the on-disk cache.
///
/// Behaviour follows `SurveyApiService.parseConfigFromJsonResponse` on Android:
/// - `messages[]` with `success: false` and a message -> backend error -> empty config
/// - optional `data` wrapper
/// - missing / null `surveys` -> empty config
/// - a survey that cannot be read is skipped, the others are kept
/// - `priority` may be a number or a numeric string
/// - the operator may be in `ruleOperator` or `operator`, as an id (number or string) or a name
enum ConfigParser {

    /// Generates an id for surveys the backend sent without `surveyId` (Android: `survey_<millis>_<random>`).
    static var makeFallbackSurveyId: () -> String = {
        let millis = Int64(Date().timeIntervalSince1970 * 1000)
        return "survey_\(millis)_\(Int.random(in: 0..<10_000))"
    }

    // MARK: - Response

    static func parseResponse(_ data: Data) -> Config {
        let root: JSONValue
        do {
            root = try JSONValue.parse(data)
        } catch {
            SDKLog.error("Error parsing config JSON: \(error)", .api)
            return .empty
        }
        guard let rootObject = root.objectValue else {
            SDKLog.error("Config response is not a JSON object", .api)
            return .empty
        }

        if let messages = rootObject["messages"]?.arrayValue {
            for message in messages {
                let success = message["success"]?.boolValue ?? true
                let text = message["message"]?.stringValue ?? ""
                if !success && !text.isEmpty {
                    SDKLog.error("Backend error in message: \(text.prefix(100))", .api)
                    return .empty
                }
            }
        }

        let configObject: [String: JSONValue]
        if let data = rootObject["data"], !data.isNull {
            guard let object = data.objectValue else {
                SDKLog.error("Config 'data' is not a JSON object", .api)
                return .empty
            }
            configObject = object
            SDKLog.debug("Parsing config from data wrapper", .api)
        } else {
            configObject = rootObject
            SDKLog.debug("Parsing config from direct JSON", .api)
        }

        return parseConfigObject(configObject) ?? .empty
    }

    /// Returns nil when there is no `surveys` array (Android returns EMPTY_CONFIG in that case).
    static func parseConfigObject(_ object: [String: JSONValue]) -> Config? {
        guard let surveysArray = object["surveys"]?.arrayValue else {
            SDKLog.warning("No surveys array found or surveys is null", .api)
            return nil
        }

        var surveys: [SurveyConfig] = []
        for (index, item) in surveysArray.enumerated() {
            guard let surveyObject = item.objectValue else {
                SDKLog.error("Error parsing survey at index \(index): not an object", .api)
                continue
            }
            surveys.append(parseSurvey(surveyObject))
        }
        SDKLog.debug("Found \(surveys.count) surveys in response", .api)

        let sdkVersion = object["sdkVersion"]?.stringValue ?? SDKConstants.sdkVersion
        if sdkVersion == "null" {
            SDKLog.warning("Invalid config values, using empty config", .api)
            return nil
        }
        let cacheDurationHours = object["cacheDurationHours"]?.int64Value ?? SDKConstants.cacheDurationHours

        return Config(sdkVersion: sdkVersion, cacheDurationHours: cacheDurationHours, surveys: surveys)
    }

    // MARK: - Survey

    static func parseSurvey(_ json: [String: JSONValue]) -> SurveyConfig {
        var survey = SurveyConfig()

        let backendId = json["surveyId"]?.stringValue ?? ""
        survey.surveyId = backendId.isEmpty ? makeFallbackSurveyId() : backendId
        survey.surveyName = json["surveyName"]?.stringValue ?? ""
        survey.baseUrl = json["baseUrl"]?.stringValue ?? ""
        survey.status = json["status"]?.boolValue ?? true

        survey.enableButtonTrigger = json["enableButtonTrigger"]?.boolValue ?? false
        survey.enableScrollTrigger = json["enableScrollTrigger"]?.boolValue ?? false
        survey.enableNavigationTrigger = json["enableNavigationTrigger"]?.boolValue ?? false
        survey.enableAppLaunchTrigger = json["enableAppLaunchTrigger"]?.boolValue ?? false
        survey.enableExitTrigger = json["enableExitTrigger"]?.boolValue ?? false
        survey.enableTabChangeTrigger = json["enableTabChangeTrigger"]?.boolValue ?? false

        if let buttonId = json["buttonTriggerId"]?.stringValue, !buttonId.isEmpty {
            survey.buttonTriggerId = buttonId
        }

        survey.triggerScreens = stringSet(json["triggerScreens"])
        survey.triggerTabs = stringSet(json["triggerTabs"])
        survey.timeDelay = json["timeDelay"]?.int64Value ?? 0
        survey.scrollThreshold = json["scrollThreshold"]?.intValue ?? 0
        survey.triggerType = json["triggerType"]?.stringValue ?? SDKConstants.defaultTriggerType

        survey.modalStyle = json["modalStyle"]?.stringValue ?? SDKConstants.defaultModalStyle
        survey.animationType = json["animationType"]?.stringValue ?? SDKConstants.defaultAnimation
        survey.backgroundColor = json["backgroundColor"]?.stringValue ?? SDKConstants.defaultBackgroundColor

        survey.probability = json["probability"]?.doubleValue ?? 1.0
        survey.maxShowsPerSession = json["maxShowsPerSession"]?.intValue ?? 0
        survey.cooldownPeriod = json["cooldownPeriod"]?.int64Value ?? 0
        survey.triggerOnce = json["triggerOnce"]?.boolValue ?? false
        survey.priority = json["priority"]?.intValue ?? SDKConstants.defaultPriority

        survey.collectDeviceId = json["collectDeviceId"]?.boolValue ?? false
        survey.collectDeviceModel = json["collectDeviceModel"]?.boolValue ?? false
        survey.collectLocation = json["collectLocation"]?.boolValue ?? false
        survey.collectAppUsage = json["collectAppUsage"]?.boolValue ?? false

        survey.customParams = parseCustomParams(json["customParams"])
        survey.exclusionRules = parseExclusionRules(json["exclusionRules"])
        return survey
    }

    private static func stringSet(_ value: JSONValue?) -> Set<String> {
        guard let array = value?.arrayValue else { return [] }
        return Set(array.compactMap { $0.stringValue })
    }

    /// Blank keys are treated as "no key", so the lookup falls back to the name / default key.
    private static func optionalKey(_ value: JSONValue?) -> String? {
        guard let text = value?.stringValue,
              !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return text
    }

    // MARK: - Custom parameters

    static func parseCustomParams(_ value: JSONValue?) -> [CustomParam] {
        guard let array = value?.arrayValue else { return [] }
        return array.compactMap { item in
            guard let object = item.objectValue,
                  let name = object["name"]?.stringValue,
                  let sourceText = object["source"]?.stringValue,
                  let source = ValueSource(rawValue: sourceText.uppercased()) else {
                SDKLog.error("Skipping invalid custom param: \(item)", .api)
                return nil
            }
            return CustomParam(name: name, source: source, key: optionalKey(object["key"]))
        }
    }

    // MARK: - Exclusion rules

    static func parseExclusionRules(_ value: JSONValue?) -> [ExclusionRule] {
        guard let array = value?.arrayValue else { return [] }
        return array.enumerated().compactMap { index, item in
            guard let object = item.objectValue else {
                SDKLog.error("Error parsing exclusion rule at index \(index)", .api)
                return nil
            }
            let sourceText = object["source"]?.stringValue ?? ValueSource.storage.rawValue
            guard let source = ValueSource(rawValue: sourceText.uppercased()) else {
                SDKLog.error("Error parsing exclusion rule: unknown source '\(sourceText)'", .api)
                return nil
            }
            return ExclusionRule(
                name: object["name"]?.stringValue ?? "rule_\(index)",
                source: source,
                key: optionalKey(object["key"]),
                value: object["value"]?.stringValue,
                ruleOperator: parseOperator(object),
                matchValue: object["matchValue"]?.stringValue ?? "",
                caseSensitive: object["caseSensitive"]?.boolValue ?? false
            )
        }
    }

    static func parseOperator(_ rule: [String: JSONValue]) -> ExclusionOperator {
        let field = rule["ruleOperator"] != nil ? "ruleOperator" : "operator"
        switch rule[field] {
        case .number(let id)?:
            return ExclusionOperator.from(id: Int(exactly: id.rounded(.towardZero)) ?? -1)
        case .string(let text)?:
            if let id = Int(text.trimmingCharacters(in: .whitespaces)) {
                return ExclusionOperator.from(id: id)
            }
            return ExclusionOperator.from(name: text) ?? .equals
        default:
            return .equals
        }
    }

    // MARK: - Cache serialization

    /// Writes a config in the same field layout the parser reads, so the cache round-trips.
    static func encode(_ config: Config) -> JSONValue {
        .object([
            "sdkVersion": .string(config.sdkVersion),
            "cacheDurationHours": .number(Double(config.cacheDurationHours)),
            "surveys": .array(config.surveys.map { encode($0) }),
        ])
    }

    static func encode(_ survey: SurveyConfig) -> JSONValue {
        var object: [String: JSONValue] = [
            "surveyId": .string(survey.surveyId),
            "surveyName": .string(survey.surveyName),
            "baseUrl": .string(survey.baseUrl),
            "status": .bool(survey.status),
            "enableButtonTrigger": .bool(survey.enableButtonTrigger),
            "enableScrollTrigger": .bool(survey.enableScrollTrigger),
            "enableNavigationTrigger": .bool(survey.enableNavigationTrigger),
            "enableAppLaunchTrigger": .bool(survey.enableAppLaunchTrigger),
            "enableExitTrigger": .bool(survey.enableExitTrigger),
            "enableTabChangeTrigger": .bool(survey.enableTabChangeTrigger),
            "triggerScreens": .array(survey.triggerScreens.sorted().map(JSONValue.string)),
            "triggerTabs": .array(survey.triggerTabs.sorted().map(JSONValue.string)),
            "timeDelay": .number(Double(survey.timeDelay)),
            "scrollThreshold": .number(Double(survey.scrollThreshold)),
            "triggerType": .string(survey.triggerType),
            "modalStyle": .string(survey.modalStyle),
            "animationType": .string(survey.animationType),
            "backgroundColor": .string(survey.backgroundColor),
            "probability": .number(survey.probability),
            "maxShowsPerSession": .number(Double(survey.maxShowsPerSession)),
            "cooldownPeriod": .number(Double(survey.cooldownPeriod)),
            "triggerOnce": .bool(survey.triggerOnce),
            "priority": .number(Double(survey.priority)),
            "collectDeviceId": .bool(survey.collectDeviceId),
            "collectDeviceModel": .bool(survey.collectDeviceModel),
            "collectLocation": .bool(survey.collectLocation),
            "collectAppUsage": .bool(survey.collectAppUsage),
            "customParams": .array(survey.customParams.map { encode($0) }),
            "exclusionRules": .array(survey.exclusionRules.map { encode($0) }),
        ]
        if let buttonId = survey.buttonTriggerId {
            object["buttonTriggerId"] = .string(buttonId)
        }
        return .object(object)
    }

    private static func encode(_ param: CustomParam) -> JSONValue {
        var object: [String: JSONValue] = [
            "name": .string(param.name),
            "source": .string(param.source.rawValue),
        ]
        if let key = param.key { object["key"] = .string(key) }
        return .object(object)
    }

    private static func encode(_ rule: ExclusionRule) -> JSONValue {
        var object: [String: JSONValue] = [
            "name": .string(rule.name),
            "source": .string(rule.source.rawValue),
            "ruleOperator": .number(Double(rule.ruleOperator.rawValue)),
            "matchValue": .string(rule.matchValue),
            "caseSensitive": .bool(rule.caseSensitive),
        ]
        if let key = rule.key { object["key"] = .string(key) }
        if let value = rule.value { object["value"] = .string(value) }
        return .object(object)
    }
}
