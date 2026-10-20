import BetterDropCore
import BetterDropUI
import SwiftUI

/// A card you can pick up and throw. Hold it a moment and it lifts off the grid and tilts as you move it; throw it
/// hard and it burns away into light as it flies off, then condenses back into its place (it was a copy that went
/// to the Mac). A gentle drag just puts it back.
struct FlingableCard<Menu: View>: View {
    let item: DropItem
    let url: URL
    let progress: Double?
    let canSend: Bool
    let macEdge: HorizontalEdge
    /// Just arrived: condense out of light the first time it's shown.
    let isFresh: Bool
    let onSend: () -> Void
    let onOpen: () -> Void
    /// How far it's been pulled towards the Mac, 0 to 1, as it moves.
    let onPull: (Double) -> Void
    let onSettled: () -> Void
    @ViewBuilder let menu: () -> Menu

    @State private var offset: CGSize = .zero
    @State private var isLifted = false
    @State private var burn: Double = 0
    @State private var heading = CGVector(dx: -1, dy: 0)
    @State private var refusals = 0

    /// How far the throw has to be heading, in points, to count.
    private static var flingDistance: CGFloat { 360 }

    var body: some View {
        DropCard(item: item, url: url, progress: progress, showsMenu: burn == 0 && !isLifted, menu: menu)
            .lightDissolve(burn, towards: heading)
            .rotation3DEffect(.degrees(isLifted ? Double(offset.width) / 9 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(isLifted ? Double(-offset.height) / 14 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .scaleEffect(isLifted ? 1.06 : 1)
            .offset(offset)
            .shadow(color: .black.opacity(isLifted ? 0.55 : 0), radius: isLifted ? 26 : 0, y: isLifted ? 16 : 0)
            .background {
                // A pool of light under a lifted card.
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Glow.ring)
                    .blur(radius: 26)
                    .opacity(isLifted ? 0.55 : 0)
                    .offset(offset)
                    .scaleEffect(0.9)
            }
            .zIndex(isLifted || burn > 0 ? 1 : 0)
            .onTapGesture(perform: onOpen)
            .gesture(fling)
            .sensoryFeedback(.selection, trigger: isLifted) { _, lifted in lifted }
            .sensoryFeedback(.error, trigger: refusals)
            .accessibilityAction(named: Text("Send to Mac"), onSend)
            .onAppear(perform: condenseIfFresh)
    }

    private var fling: some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case let .second(true, drag) = value else { return }
                if !isLifted { withAnimation(.spring(duration: 0.3, bounce: 0.4)) { isLifted = true } }
                if let drag {
                    offset = drag.translation
                    let towardsMac = macEdge == .leading ? -drag.translation.width : drag.translation.width
                    onPull(min(1, max(0, towardsMac / 180)))
                }
            }
            .onEnded { value in
                onPull(0)
                guard case let .second(true, drag?) = value else { return settle() }
                let throwTo = drag.predictedEndTranslation
                let distance = hypot(throwTo.width, throwTo.height)
                guard distance > Self.flingDistance else { return settle() }
                guard canSend else {
                    refusals += 1
                    return settle()
                }
                throwAway(towards: throwTo, distance: distance)
            }
    }

    private func settle() {
        withAnimation(.spring(duration: 0.5, bounce: 0.35)) {
            offset = .zero
            isLifted = false
        }
    }

    private func throwAway(towards target: CGSize, distance: CGFloat) {
        heading = CGVector(dx: target.width, dy: target.height)
        onSend()
        let scale = 900 / max(distance, 1)
        withAnimation(.easeIn(duration: 0.45)) {
            offset = CGSize(width: target.width * scale, height: target.height * scale)
            burn = 1
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            var instantly = Transaction()
            instantly.disablesAnimations = true
            withTransaction(instantly) {
                offset = .zero
                isLifted = false
                heading = CGVector(dx: 0, dy: -1)
            }
            withAnimation(.easeOut(duration: 0.8)) { burn = 0 }
        }
    }

    private func condenseIfFresh() {
        guard isFresh else { return }
        heading = CGVector(dx: macEdge == .leading ? 1 : -1, dy: 0)
        var instantly = Transaction()
        instantly.disablesAnimations = true
        withTransaction(instantly) { burn = 1 }
        withAnimation(.easeOut(duration: 1.1).delay(0.1)) { burn = 0 }
        Task {
            try? await Task.sleep(for: .seconds(1.3))
            onSettled()
        }
    }
}
