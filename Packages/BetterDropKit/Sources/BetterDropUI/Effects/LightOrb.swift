import SwiftUI

/// BetterDrop's mark: a living drop of iridescent light.
///
/// - `energy` 0–1: how awake it is. Brighter, bigger halo.
/// - `lean`: stretches it towards a point, in units of its radius (the Mac's side, as you bring the phone close).
/// - `charge` 0–1: how long it's been held. It swirls faster, swells, and a ring of light closes in.
///
/// Changes animate: wrap them in `withAnimation` or use `.animation`.
public struct LightOrb: View, Animatable {
    public var energy: Double
    public var lean: CGVector
    public var charge: Double
    public var isAnimating: Bool

    public init(energy: Double = 0.4, lean: CGVector = .zero, charge: Double = 0, isAnimating: Bool = true) {
        self.energy = energy
        self.lean = lean
        self.charge = charge
        self.isAnimating = isAnimating
    }

    public nonisolated var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(energy, charge), AnimatablePair(lean.dx, lean.dy)) }
        set {
            energy = newValue.first.first
            charge = newValue.first.second
            lean = CGVector(dx: newValue.second.first, dy: newValue.second.second)
        }
    }

    public var body: some View {
        ShaderClock(paused: !isAnimating) { time in
            Rectangle()
                .colorEffect(Shaders.library.Orb(
                    .boundingRect, .float(time), .float(Float(energy)),
                    .float2(Float(lean.dx), Float(lean.dy)), .float(Float(charge))))
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    LightOrb(energy: 0.8, lean: CGVector(dx: -0.6, dy: 0), charge: 0.3)
        .frame(width: 320, height: 320)
        .background(.black)
}
