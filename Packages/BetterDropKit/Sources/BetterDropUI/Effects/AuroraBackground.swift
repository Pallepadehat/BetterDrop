import SwiftUI

/// A slow, dark aurora: a mesh gradient in the glow's colours whose points drift, brightening as `intensity`
/// rises. Behind the connect screen, it wakes up as you bring the phone to the Mac.
public struct AuroraBackground: View {
    public var intensity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(intensity: Double) {
        self.intensity = intensity
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = Float(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000))
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5 + 0.2 * sin(t * 0.3), 0], [1, 0],
                [0, 0.5 + 0.15 * cos(t * 0.4)], [0.5 + 0.18 * sin(t * 0.5), 0.5 + 0.18 * cos(t * 0.35)], [1, 0.5 + 0.15 * sin(t * 0.45)],
                [0, 1], [0.5 + 0.2 * cos(t * 0.25), 1], [1, 1],
            ], colors: colors)
        }
        .opacity(0.25 + 0.75 * intensity)
        .animation(.easeInOut(duration: 0.8), value: intensity)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var colors: [Color] {
        let dark = Color.black
        let glow = Glow.colors
        let level = 0.12 + 0.5 * intensity
        return [
            dark, glow[0].opacity(level * 0.6), dark,
            glow[3].opacity(level * 0.7), glow[6].opacity(level), glow[2].opacity(level * 0.7),
            dark, glow[4].opacity(level * 0.6), dark,
        ].map { $0.mix(with: .black, by: 0.35) }
    }
}

#Preview {
    AuroraBackground(intensity: 0.8)
}
