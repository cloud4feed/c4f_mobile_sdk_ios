import Foundation

/// Platform-independent colour (components 0...1).
struct RGBAColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let white = RGBAColor(red: 1, green: 1, blue: 1, alpha: 1)

    /// Parses `#RGB`, `#RRGGBB` and `#AARRGGBB` (Android `Color.parseColor` order: alpha first).
    /// Anything else gives `fallback`.
    init(hex: String, fallback: RGBAColor = .white) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.allSatisfy({ $0.isHexDigit }), let value = UInt64(text, radix: 16) else {
            self = fallback
            return
        }
        switch text.count {
        case 3:
            self.init(red: Double((value >> 8) & 0xF) / 15,
                      green: Double((value >> 4) & 0xF) / 15,
                      blue: Double(value & 0xF) / 15,
                      alpha: 1)
        case 6:
            self.init(red: Double((value >> 16) & 0xFF) / 255,
                      green: Double((value >> 8) & 0xFF) / 255,
                      blue: Double(value & 0xFF) / 255,
                      alpha: 1)
        case 8:
            self.init(red: Double((value >> 16) & 0xFF) / 255,
                      green: Double((value >> 8) & 0xFF) / 255,
                      blue: Double(value & 0xFF) / 255,
                      alpha: Double((value >> 24) & 0xFF) / 255)
        default:
            self = fallback
        }
    }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}
