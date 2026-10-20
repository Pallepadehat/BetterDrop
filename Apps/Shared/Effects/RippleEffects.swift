import SwiftUI

extension View {
    /// Sends a ripple out from `origin` every time `trigger` changes.
    func ripple<Trigger: Equatable>(at origin: CGPoint, trigger: Trigger, amplitude: Double = 14, duration: TimeInterval = 2.4) -> some View {
        modifier(RippleEffect(origin: origin, trigger: trigger, amplitude: amplitude, duration: duration))
    }

    /// Makes the edge of the view nearest the Mac shimmer like water, more the closer it is (0 to 1).
    func edgeWarp(side: EdgeSide, closeness: Double) -> some View {
        modifier(EdgeWarpEffect(side: side, closeness: closeness))
    }
}

nonisolated enum EdgeSide: Equatable, Sendable {
    case left, right

    func origin(in size: CGSize) -> CGPoint {
        CGPoint(x: self == .left ? 0 : size.width, y: size.height * 0.45)
    }
}

private struct RippleEffect<Trigger: Equatable>: ViewModifier {
    let origin: CGPoint
    let trigger: Trigger
    let amplitude: Double
    let duration: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, elapsed in
            view.visualEffect { view, _ in
                view.layerEffect(
                    ShaderLibrary.Ripple(.float2(origin), .float(elapsed), .float(amplitude), .float(15), .float(4.5), .float(1100)),
                    maxSampleOffset: CGSize(width: amplitude, height: amplitude),
                    isEnabled: !reduceMotion && elapsed > 0 && elapsed < duration)
            }
        } keyframes: { _ in
            MoveKeyframe(0)
            LinearKeyframe(duration, duration: duration)
        }
    }
}

private struct EdgeWarpEffect: ViewModifier {
    let side: EdgeSide
    let closeness: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let start = Date.now

    func body(content: Content) -> some View {
        let active = closeness > 0.02 && !reduceMotion
        TimelineView(.animation(paused: !active)) { timeline in
            let time = timeline.date.timeIntervalSince(start)
            content.visualEffect { view, proxy in
                view.layerEffect(
                    ShaderLibrary.EdgeWarp(.float2(proxy.size), .float(side == .left ? 0 : 1), .float(closeness), .float(time)),
                    maxSampleOffset: CGSize(width: 12, height: 12),
                    isEnabled: active)
            }
        }
    }
}
