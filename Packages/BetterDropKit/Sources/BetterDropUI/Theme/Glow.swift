import SwiftUI

/// BetterDrop's colours: the warm-to-cool sweep of light the shaders draw, for when SwiftUI needs them too.
public enum Glow {
    public static let colors: [Color] = [
        Color(red: 1.00, green: 0.62, blue: 0.38), // apricot
        Color(red: 1.00, green: 0.42, blue: 0.56), // rose
        Color(red: 0.86, green: 0.40, blue: 0.95), // orchid
        Color(red: 0.58, green: 0.50, blue: 1.00), // violet
        Color(red: 0.45, green: 0.66, blue: 1.00), // periwinkle
    ]

    /// For text and symbols that glow.
    public static let text = LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)

    /// Round the colour wheel, for rings.
    public static let ring = AngularGradient(colors: colors + [colors[0]], center: .center)

    /// The near-black every surface sits on.
    public static let ink = Color(red: 0.03, green: 0.03, blue: 0.05)
}

public extension View {
    /// Fills text (or a symbol) with the glow gradient.
    func glowingForeground() -> some View {
        foregroundStyle(Glow.text)
    }
}

public extension Font {
    /// BetterDrop's display type: SF Pro Rounded, heavy, a little tight.
    static func brand(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
