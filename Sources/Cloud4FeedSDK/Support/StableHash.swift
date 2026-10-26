import Foundation

/// Hash that stays the same across app launches and platforms.
///
/// Swift's `hashValue` / `Hasher` is randomly seeded per process, so it cannot be used for
/// anything that is persisted (cache keys, "trigger once" memory). FNV-1a 64-bit is enough here:
/// the hash only tells "same user parameters" from "different user parameters".
enum StableHash {
    static func fnv1a64(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// Order-independent hash of a parameter map.
    static func parameters(_ parameters: [String: String]) -> String {
        let canonical = parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)\u{1F}\($0.value)" }
            .joined(separator: "\u{1E}")
        return fnv1a64(canonical)
    }
}
