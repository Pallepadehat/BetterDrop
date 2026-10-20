import SwiftUI

/// The light that blooms out of the side of the Mac's screen where the phone is: a soft white core with the glow's
/// colours swirling round it, half of it beyond the edge, as if the phone were shining through.
public struct EdgeBloom: View {
    public enum Edge: String, Sendable, CaseIterable, Codable {
        case leading, trailing
    }

    /// 0 is off, about 0.35 is "the phone is here", 1 is a file passing through.
    public var intensity: Double
    public var edge: Edge
    /// Sonar rings rolling out of the edge, 0 to 1: how close the phone is.
    public var waves: Double
    /// Changes each time something arrives or leaves, sending a shockwave across the screen.
    public var burst: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(intensity: Double, edge: Edge, waves: Double = 0, burst: Int = 0) {
        self.intensity = intensity
        self.edge = edge
        self.waves = waves
        self.burst = burst
    }

    private var edgePoint: UnitPoint { UnitPoint(x: edge == .trailing ? 1 : 0, y: 0.5) }

    public var body: some View {
        ZStack {
            SonarRings(intensity: waves, center: edgePoint, reach: 1.1, lineWidth: 3)
            bloom
            Shockwave(trigger: burst, center: edgePoint)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var bloom: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let diameter = height * (0.55 + 0.5 * intensity)
            let x = edge == .trailing ? proxy.size.width : 0
            TimelineView(.animation(minimumInterval: 1 / 30, paused: intensity == 0 || reduceMotion)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let breathe = 1 + 0.04 * sin(time * 1.6)
                ZStack {
                    // The colours, drifting round the core.
                    ForEach(Glow.colors.indices, id: \.self) { index in
                        let phase = Double(index) / Double(Glow.colors.count) * 2 * .pi
                        let swirl = time * 0.35 + phase
                        Circle()
                            .fill(Glow.colors[index])
                            .frame(width: diameter * 0.62, height: diameter * 0.62)
                            .offset(x: cos(swirl) * diameter * 0.2, y: sin(swirl) * diameter * 0.3)
                            .blur(radius: diameter * 0.16)
                            .opacity(0.75)
                    }
                    // The bright core.
                    Circle()
                        .fill(RadialGradient(colors: [.white, .white.opacity(0.92), .white.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: diameter * 0.42))
                        .frame(width: diameter * 0.9, height: diameter * 0.9)
                        .blur(radius: diameter * 0.04)
                }
                .scaleEffect(breathe)
                .frame(width: diameter, height: diameter)
                .position(x: x, y: height / 2)
                .blendMode(.screen)
            }
        }
        .opacity(min(1, intensity * 1.6))
        .animation(.spring(duration: 0.8, bounce: 0.15), value: intensity)
    }
}

#Preview {
    EdgeBloom(intensity: 0.6, edge: .trailing, waves: 0.8)
        .frame(width: 900, height: 560)
        .background(LinearGradient(colors: [.teal, .indigo], startPoint: .top, endPoint: .bottom))
}
