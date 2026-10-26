import Foundation

/// On-device exclusion rules (Android: `ExclusionRuleEvaluator`). A survey is excluded as soon as
/// one rule matches. A missing value is compared as an empty string.
struct ExclusionEvaluator {
    let resolver: ValueResolver

    func shouldExclude(_ rules: [ExclusionRule]) -> Bool {
        guard !rules.isEmpty else { return false }
        for rule in rules where evaluate(rule) {
            SDKLog.debug("User excluded by rule: \(rule.name)", .rules)
            return true
        }
        return false
    }

    func evaluate(_ rule: ExclusionRule) -> Bool {
        let actual = resolver.value(source: rule.source, key: rule.key, name: rule.name) ?? ""
        let result = Self.matches(actual: actual,
                                  operator: rule.ruleOperator,
                                  matchValue: rule.matchValue,
                                  caseSensitive: rule.caseSensitive)
        SDKLog.debug("Rule '\(rule.name)': '\(actual)' \(rule.ruleOperator) '\(rule.matchValue)' -> \(result)", .rules)
        return result
    }

    /// Pure comparison, identical to the Android operator table.
    static func matches(actual: String,
                        operator op: ExclusionOperator,
                        matchValue: String,
                        caseSensitive: Bool) -> Bool {
        let match = caseSensitive ? matchValue : matchValue.lowercased()
        let compare = caseSensitive ? actual : actual.lowercased()

        switch op {
        case .equals: return compare == match
        case .notEquals: return compare != match
        case .contains: return contains(compare, match)
        case .notContains: return !contains(compare, match)
        case .startsWith: return compare.hasPrefix(match)
        case .endsWith: return compare.hasSuffix(match)
        // LENGTH: the value's length equals the number in matchValue.
        case .length: return numeric(String(actual.count), matchValue, ==)
        case .greaterThan: return numeric(actual, matchValue, >)
        case .lessThan: return numeric(actual, matchValue, <)
        case .greaterOrEqual: return numeric(actual, matchValue, >=)
        case .lessOrEqual: return numeric(actual, matchValue, <=)
        case .`in`: return isInList(compare, matchValue, ignoreCase: !caseSensitive)
        case .notIn: return !isInList(compare, matchValue, ignoreCase: !caseSensitive)
        case .empty: return isBlank(actual)
        case .notEmpty: return !isBlank(actual)
        }
    }

    /// Kotlin `contains("")` is true; make that explicit instead of relying on Foundation.
    private static func contains(_ text: String, _ part: String) -> Bool {
        part.isEmpty || text.contains(part)
    }

    /// Both sides must be numbers, otherwise the rule does not match.
    private static func numeric(_ actual: String, _ match: String, _ comparator: (Double, Double) -> Bool) -> Bool {
        guard let a = Double(actual.trimmingCharacters(in: .whitespaces)),
              let b = Double(match.trimmingCharacters(in: .whitespaces)) else { return false }
        return comparator(a, b)
    }

    /// Comma-separated list, items trimmed.
    private static func isInList(_ value: String, _ list: String, ignoreCase: Bool) -> Bool {
        list.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains { ignoreCase ? $0.lowercased() == value.lowercased() : $0 == value }
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
