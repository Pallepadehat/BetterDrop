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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(intensity: Double, edge: Edge) {
        self.intensity = intensity
        self.edge = edge
    }

    public var body: some View {
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
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    EdgeBloom(intensity: 1, edge: .trailing)
        .frame(width: 900, height: 560)
        .background(LinearGradient(colors: [.teal, .indigo], startPoint: .top, endPoint: .bottom))
}
