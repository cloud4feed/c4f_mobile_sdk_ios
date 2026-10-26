import Foundation

/// Why a survey may not be shown right now.
enum BlockReason: String, Equatable {
    case disabled
    case emptyBaseUrl
    case excluded
    case alreadyShownOnce
    case maxShowsReached
    case cooldown
}

enum EligibilityDecision: Equatable {
    case allowed
    case blocked(BlockReason)

    var isAllowed: Bool { self == .allowed }
}

/// Display rules (Android: `canShowSurvey` + `recordSurveyShown`). Same order as Android:
/// status -> baseUrl -> exclusion rules -> triggerOnce -> maxShowsPerSession -> cooldown.
/// `probability` is read but not applied (Android does not apply it either).
final class Eligibility {
    private let exclusion: ExclusionEvaluator
    private let triggerOnce: TriggerOnceStore
    private let now: () -> Date

    /// Parameters given to `initialize`; part of the "trigger once" identity.
    var userParameters: [String: String]

    private(set) var shownCount: [String: Int] = [:]
    private(set) var lastShown: [String: Date] = [:]

    init(exclusion: ExclusionEvaluator,
         triggerOnce: TriggerOnceStore,
         userParameters: [String: String] = [:],
         now: @escaping () -> Date = Date.init) {
        self.exclusion = exclusion
        self.triggerOnce = triggerOnce
        self.userParameters = userParameters
        self.now = now
    }

    func decision(for survey: SurveyConfig) -> EligibilityDecision {
        if !survey.status { return .blocked(.disabled) }
        if survey.baseUrl.isEmpty { return .blocked(.emptyBaseUrl) }
        if exclusion.shouldExclude(survey.exclusionRules) { return .blocked(.excluded) }
        if survey.triggerOnce && triggerOnce.hasShown(surveyId: survey.surveyId, userParameters: userParameters) {
            return .blocked(.alreadyShownOnce)
        }
        let count = shownCount[survey.surveyId] ?? 0
        if survey.maxShowsPerSession > 0 && count >= survey.maxShowsPerSession {
            return .blocked(.maxShowsReached)
        }
        if survey.cooldownPeriod > 0, let last = lastShown[survey.surveyId] {
            let elapsedMillis = now().timeIntervalSince(last) * 1000
            if elapsedMillis < Double(survey.cooldownPeriod) { return .blocked(.cooldown) }
        }
        return .allowed
    }

    /// Exclusion rules only (Android `isUserExcluded(surveyId)`).
    func isExcluded(_ survey: SurveyConfig) -> Bool {
        exclusion.shouldExclude(survey.exclusionRules)
    }

    func canShow(_ survey: SurveyConfig) -> Bool {
        let result = decision(for: survey)
        if case .blocked(let reason) = result {
            SDKLog.debug("Survey \(survey.surveyId) cannot be shown: \(reason.rawValue)", .rules)
        }
        return result.isAllowed
    }

    /// Call when a survey is actually displayed.
    func recordShown(_ survey: SurveyConfig) {
        shownCount[survey.surveyId, default: 0] += 1
        lastShown[survey.surveyId] = now()
        if survey.triggerOnce {
            triggerOnce.markShown(surveyId: survey.surveyId, userParameters: userParameters)
        }
        SDKLog.debug("Survey shown: \(survey.surveyId), count: \(shownCount[survey.surveyId] ?? 0)", .rules)
    }

    /// Android resets the per-session counters whenever a configuration is applied.
    func resetSessionCounters() {
        shownCount.removeAll()
        lastShown.removeAll()
    }

    func clearTriggerOnceHistory() {
        triggerOnce.clear()
    }
}
