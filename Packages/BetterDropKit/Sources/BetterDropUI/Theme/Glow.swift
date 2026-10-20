import SwiftUI

/// The colours of the glow: the warm-to-cool sweep of light around the edge of the screen.
public enum Glow {
    public static let colors: [Color] = [
        Color(red: 0.74, green: 0.51, blue: 0.95), // lavender
        Color(red: 0.96, green: 0.73, blue: 0.92), // pink
        Color(red: 0.55, green: 0.62, blue: 1.00), // periwinkle
        Color(red: 1.00, green: 0.40, blue: 0.47), // coral
        Color(red: 1.00, green: 0.73, blue: 0.44), // apricot
        Color(red: 0.78, green: 0.53, blue: 1.00), // violet
        Color(red: 0.98, green: 0.30, blue: 0.75), // magenta
    ]

    /// The gradient for text that glows, like a Mac's name while you hold the phone to it.
    public static let text = LinearGradient(
        colors: [Color(red: 1.0, green: 0.55, blue: 0.25), Color(red: 1.0, green: 0.33, blue: 0.55),
                 Color(red: 0.86, green: 0.36, blue: 0.93), Color(red: 0.55, green: 0.5, blue: 1.0)],
        startPoint: .leading, endPoint: .trailing)

    /// The colours spread around the edge in a new random arrangement, so the light keeps moving.
    static func randomStops() -> [Gradient.Stop] {
        colors.map { Gradient.Stop(color: $0, location: Double.random(in: 0...1)) }
            .sorted { $0.location < $1.location }
    }
}

public extension View {
    /// Fills text (or anything) with the glow gradient.
    func glowingForeground() -> some View {
        foregroundStyle(Glow.text)
    }
}
