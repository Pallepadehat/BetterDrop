import BetterDropCore
import SwiftUI

/// The Mac's side of the light: a curtain flowing out of the screen edge the phone is held against. It follows
/// the phone's closeness, rolls rings out while a phone is close, and sends a front of light across the screen
/// each time `surge` changes.
public struct LightPortal: View, Animatable {
    public var intensity: Double
    public var waves: Double
    public var side: Side
    public var surge: Int

    public init(intensity: Double, waves: Double = 0, side: Side, surge: Int = 0) {
        self.intensity = intensity
        self.waves = waves
        self.side = side
        self.surge = surge
    }

    public nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(intensity, waves) }
        set {
            intensity = newValue.first
            waves = newValue.second
        }
    }

    public var body: some View {
        SurgeClock(trigger: surge, duration: 1.5, isIdle: intensity < 0.002 && waves < 0.002) { time, progress in
            Rectangle()
                .colorEffect(Shaders.library.Portal(
                    .boundingRect, .float(time), .float(Float(intensity)),
                    .float(side == .right ? 1 : 0), .float(Float(waves)), .float(Float(progress))))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    LightPortal(intensity: 0.6, waves: 0.7, side: .right)
        .frame(width: 600, height: 700)
        .background(LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom))
}
