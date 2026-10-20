import SwiftUI

enum Shaders {
    static let library = ShaderLibrary.bundle(.module)
}

/// Redraws its content every frame while running, handing it the time in seconds. Paused, it draws once and stops,
/// so an idle effect costs nothing.
struct ShaderClock<Content: View>: View {
    var paused = false
    var frameRate: Double = 60
    @ViewBuilder var content: (Float) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / frameRate, paused: paused)) { timeline in
            // Wrapped every hour so the shader's floats stay precise.
            let seconds = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            content(Float(reduceMotion ? seconds * 0.25 : seconds))
        }
    }
}

/// A ``ShaderClock`` that also plays a surge, 0 → 1 over `duration`, each time `trigger` changes. While `isIdle`
/// and not surging it draws nothing at all.
struct SurgeClock<Content: View>: View {
    var trigger: Int
    var duration: TimeInterval
    var isIdle: Bool
    @ViewBuilder var content: (_ time: Float, _ surge: Double) -> Content

    @State private var started: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !isIdle || started != nil {
                TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
                    let seconds = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                    let surge = started.map { min(1, timeline.date.timeIntervalSince($0) / duration) } ?? 0
                    content(Float(reduceMotion ? seconds * 0.25 : seconds), surge >= 1 ? 0 : surge)
                }
            }
        }
        .onChange(of: trigger) {
            let start = Date.now
            started = start
            Task {
                try? await Task.sleep(for: .seconds(duration))
                if started == start { started = nil }
            }
        }
    }
}
