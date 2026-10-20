import SwiftUI

/// A slow, dark aurora behind everything, brightening with `intensity`. Runs at 30 frames a second: it moves
/// slowly enough not to need more.
public struct AuroraBackground: View, Animatable {
    public var intensity: Double

    public init(intensity: Double) {
        self.intensity = intensity
    }

    public nonisolated var animatableData: Double {
        get { intensity }
        set { intensity = newValue }
    }

    public var body: some View {
        ShaderClock(frameRate: 30) { time in
            Rectangle()
                .colorEffect(Shaders.library.Aurora(.boundingRect, .float(time), .float(Float(intensity))))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
