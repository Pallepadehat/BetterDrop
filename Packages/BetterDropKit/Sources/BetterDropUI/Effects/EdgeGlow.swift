import SwiftUI

/// Light hugging the edge of the screen. It leans towards `emphasis` (where the Mac is) and flares each time
/// `surge` changes. At zero it's gone completely, and costs nothing.
public struct EdgeGlow: View, Animatable {
    public var intensity: Double
    public var emphasis: HorizontalEdge?
    public var surge: Int
    public var cornerRadius: CGFloat

    public init(intensity: Double, emphasis: HorizontalEdge? = nil, surge: Int = 0, cornerRadius: CGFloat = EdgeGlow.screenCornerRadius) {
        self.intensity = intensity
        self.emphasis = emphasis
        self.surge = surge
        self.cornerRadius = cornerRadius
    }

    public nonisolated var animatableData: Double {
        get { intensity }
        set { intensity = newValue }
    }

    /// Close to the corners of a modern iPhone's screen.
    public static var screenCornerRadius: CGFloat {
        #if os(iOS)
        55
        #else
        18
        #endif
    }

    public var body: some View {
        SurgeClock(trigger: surge, duration: 1.1, isIdle: intensity < 0.001) { time, progress in
            Rectangle()
                .colorEffect(Shaders.library.EdgeGlow(
                    .boundingRect, .float(time), .float(Float(intensity)),
                    .float(emphasis == .leading ? -1 : emphasis == .trailing ? 1 : 0),
                    .float(Float(cornerRadius)), .float(Float(progress > 0 ? sin(progress * .pi) : 0))))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    EdgeGlow(intensity: 0.8, emphasis: .leading)
        .background(.black)
}
