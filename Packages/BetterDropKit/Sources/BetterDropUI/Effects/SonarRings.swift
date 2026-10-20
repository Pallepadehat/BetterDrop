import SwiftUI

/// Rings of light rolling outward, like sonar. The higher the intensity, the more rings, the faster and the
/// brighter: on the phone they circle the Connect button, on the Mac they roll out of the screen edge.
public struct SonarRings: View {
    /// 0 to 1.
    public var intensity: Double
    /// Where the rings start, in unit coordinates of the view. (1, 0.5) is the middle of the right edge.
    public var center: UnitPoint
    /// How far they travel, as a multiple of the view's shorter side.
    public var reach: CGFloat
    public var lineWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(intensity: Double, center: UnitPoint = .center, reach: CGFloat = 0.6, lineWidth: CGFloat = 2) {
        self.intensity = intensity
        self.center = center
        self.reach = reach
        self.lineWidth = lineWidth
    }

    private static let count = 4

    public var body: some View {
        TimelineView(.animation(paused: intensity == 0 || reduceMotion)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                // Closer is faster: one ring every 1.6 s far away, every 0.55 s touching.
                let period = 1.6 - 1.05 * intensity
                let origin = CGPoint(x: center.x * size.width, y: center.y * size.height)
                let maximum = min(size.width, size.height) * reach * (0.7 + 0.6 * intensity)
                let gradient = Gradient(colors: Glow.colors + [Glow.colors[0]])
                for index in 0..<Self.count {
                    let phase = ((time / (period * Double(Self.count))) + Double(index) / Double(Self.count))
                        .truncatingRemainder(dividingBy: 1)
                    let radius = maximum * phase
                    let opacity = pow(1 - phase, 1.6) * intensity
                    let rect = CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2)
                    let ring = Path(ellipseIn: rect)
                    var layer = context
                    layer.opacity = opacity
                    layer.addFilter(.blur(radius: 1 + 6 * phase))
                    layer.stroke(ring, with: .conicGradient(gradient, center: origin, angle: .radians(time * 0.8)),
                                 lineWidth: lineWidth * (1 + 2.5 * (1 - phase)))
                }
            }
        }
        .opacity(intensity == 0 ? 0 : 1)
        .animation(.easeInOut(duration: 0.6), value: intensity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One rainbow shockwave that crosses the view each time `trigger` changes: a file arriving or leaving.
public struct Shockwave: View {
    public var trigger: Int
    public var center: UnitPoint

    public init(trigger: Int, center: UnitPoint) {
        self.trigger = trigger
        self.center = center
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let span = hypot(size.width, size.height)
            Circle()
                .stroke(AngularGradient(colors: Glow.colors + [Glow.colors[0]], center: .center), lineWidth: 1)
                .frame(width: 10, height: 10)
                .keyframeAnimator(initialValue: Wave(), trigger: trigger) { ring, wave in
                    ring
                        .scaleEffect(wave.scale)
                        .opacity(wave.opacity)
                        .blur(radius: wave.scale / 30)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        MoveKeyframe(1)
                        CubicKeyframe(span / 10 * 2.2, duration: 1.3)
                    }
                    KeyframeTrack(\.opacity) {
                        MoveKeyframe(0)
                        LinearKeyframe(1, duration: 0.08)
                        LinearKeyframe(0, duration: 1.2)
                    }
                }
                .position(x: center.x * size.width, y: center.y * size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct Wave {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }
}
