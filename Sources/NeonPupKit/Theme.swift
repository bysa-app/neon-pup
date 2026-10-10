import SwiftUI

/// Neon Pup design tokens. Contrast checked: text on night 15:1, textDim on night 8:1,
/// night on pink 6.5:1, teal on nightRaised 11:1.
public enum Theme {
    public static let night = Color(red: 0.07, green: 0.06, blue: 0.16)
    public static let nightRaised = Color(red: 0.13, green: 0.11, blue: 0.26)
    public static let pink = Color(red: 1.00, green: 0.31, blue: 0.85)
    public static let purple = Color(red: 0.61, green: 0.36, blue: 1.00)
    public static let teal = Color(red: 0.18, green: 0.95, blue: 0.88)
    public static let blush = Color(red: 1.00, green: 0.84, blue: 0.96)
    public static let text = Color(red: 0.96, green: 0.94, blue: 1.00)
    public static let textDim = Color(red: 0.70, green: 0.67, blue: 0.86)
    public static let corner: CGFloat = 18
    public static let panelWidth: CGFloat = 320

    public static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

public extension View {
    func neonGlow(_ color: Color, radius: CGFloat = 8) -> some View {
        shadow(color: color.opacity(0.75), radius: radius).shadow(color: color.opacity(0.35), radius: radius * 2)
    }
}
