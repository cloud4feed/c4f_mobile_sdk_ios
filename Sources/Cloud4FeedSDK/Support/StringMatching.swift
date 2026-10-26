import Foundation

extension String {
    /// Case-insensitive "contains" that does not depend on the device language
    /// (Kotlin `contains(other, ignoreCase = true)`). `localizedCaseInsensitiveContains` would treat
    /// "I"/"i" differently on a Turkish device. An empty `other` matches, as in Kotlin.
    func c4fContainsIgnoringCase(_ other: String) -> Bool {
        if other.isEmpty { return true }
        return range(of: other, options: [.caseInsensitive], range: nil, locale: nil) != nil
    }
}
