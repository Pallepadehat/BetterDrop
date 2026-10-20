import SwiftUI

/// Light running around the edge of the screen: what you see on the phone while it's next to the Mac, and when a
/// file arrives or flies off.
///
/// Four strokes of the same moving gradient, each wider and softer than the last, so it reads as light rather than
/// a line. `intensity` goes from 0 (gone) to 1 (blazing).
public struct GlowBorder: View {
    public var intensity: Double
    public var cornerRadius: CGFloat

    @State private var stops = Glow.randomStops()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(intensity: Double, cornerRadius: CGFloat = GlowBorder.screenCornerRadius) {
        self.intensity = intensity
        self.cornerRadius = cornerRadius
    }

    /// Close to the corners of a modern iPhone's screen. The Mac uses it for its panels' corners.
    public static var screenCornerRadius: CGFloat {
        #if os(iOS)
        55
        #else
        16
        #endif
    }

    private static let layers: [(width: CGFloat, blur: CGFloat)] = [(5, 0), (9, 4), (13, 12), (18, 22)]

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: intensity == 0 || reduceMotion)) { timeline in
            let angle = Angle.degrees(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 360) * 40)
            let gradient = AngularGradient(stops: stops, center: .center, angle: angle)
            ZStack {
                ForEach(Self.layers.indices, id: \.self) { index in
                    let layer = Self.layers[index]
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(gradient, lineWidth: layer.width * (0.6 + 0.4 * intensity))
                        .blur(radius: layer.blur)
                }
            }
        }
        .opacity(intensity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.5), value: intensity)
        .task(id: intensity > 0 && !reduceMotion) {
            guard intensity > 0, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeInOut(duration: 0.6)) { stops = Glow.randomStops() }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Color.black
        GlowBorder(intensity: 1)
    }
}
