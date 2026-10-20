import SwiftUI

public extension View {
    /// Burns the view away into light from the side it's heading as `progress` goes 0 to 1; run it backwards and
    /// the view condenses out of light.
    func lightDissolve(_ progress: Double, towards direction: CGVector) -> some View {
        modifier(DissolveEffect(progress: progress, direction: direction))
    }

    /// Sends a ripple through the view from `origin` each time `trigger` changes.
    func ripple(at origin: CGPoint, trigger: Int, amplitude: Double = 14, duration: TimeInterval = 2.4) -> some View {
        modifier(RippleEffect(origin: origin, trigger: trigger, amplitude: amplitude, duration: duration))
    }
}

private struct DissolveEffect: ViewModifier, Animatable {
    var progress: Double
    var direction: CGVector

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let length = max(0.001, hypot(direction.dx, direction.dy))
        content.layerEffect(
            Shaders.library.Dissolve(.boundingRect, .float(Float(progress)),
                                     .float2(Float(direction.dx / length), Float(direction.dy / length))),
            maxSampleOffset: .zero,
            isEnabled: progress > 0.001)
    }
}

private struct RippleEffect: ViewModifier {
    let origin: CGPoint
    let trigger: Int
    let amplitude: Double
    let duration: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let reduceMotion = reduceMotion, origin = origin, amplitude = amplitude, duration = duration
        return content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, elapsed in
            view.layerEffect(
                Shaders.library.Ripple(.float2(origin), .float(Float(elapsed)), .float(Float(amplitude)),
                                       .float(15), .float(4.5), .float(1100)),
                maxSampleOffset: CGSize(width: amplitude, height: amplitude),
                isEnabled: !reduceMotion && elapsed > 0 && elapsed < duration)
        } keyframes: { _ in
            MoveKeyframe(0)
            LinearKeyframe(duration, duration: duration)
        }
    }
}
