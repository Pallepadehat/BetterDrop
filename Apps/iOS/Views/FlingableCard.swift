import BetterDropCore
import BetterDropUI
import SwiftUI

/// A card you can pick up and throw. Hold it for a moment and it lifts off the grid; fling it hard in any direction
/// and it flies off the screen, to the Mac. A gentle drag just puts it back.
struct FlingableCard<Menu: View>: View {
    let item: DropItem
    let url: URL
    let progress: Double?
    let canSend: Bool
    let onSend: () -> Void
    let onOpen: () -> Void
    @ViewBuilder let menu: () -> Menu

    @State private var offset: CGSize = .zero
    @State private var isLifted = false
    @State private var isGone = false
    @State private var refusals = 0

    /// How far the throw has to be heading, in points, to count as a fling.
    private static var flingDistance: CGFloat { 380 }

    var body: some View {
        ItemCard(item: item, url: url, progress: progress, menu: menu)
            .scaleEffect(isLifted ? 1.07 : 1)
            .rotationEffect(.degrees(Double(offset.width) / 18))
            .offset(offset)
            .opacity(isGone ? 0 : 1)
            .shadow(color: .black.opacity(isLifted ? 0.5 : 0), radius: isLifted ? 24 : 0, y: isLifted ? 14 : 0)
            .shadow(color: Glow.colors[6].opacity(isLifted ? 0.45 : 0), radius: 30)
            .zIndex(isLifted || isGone ? 1 : 0)
            .onTapGesture(perform: onOpen)
            .gesture(fling)
            .sensoryFeedback(.selection, trigger: isLifted) { _, lifted in lifted }
            .sensoryFeedback(.error, trigger: refusals)
            .accessibilityAction(named: Text("Send to Mac"), onSend)
    }

    private var fling: some Gesture {
        LongPressGesture(minimumDuration: 0.18)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case let .second(true, drag) = value else { return }
                if !isLifted { withAnimation(.spring(duration: 0.25)) { isLifted = true } }
                if let drag { offset = drag.translation }
            }
            .onEnded { value in
                guard case let .second(true, drag?) = value else { return settle() }
                let heading = drag.predictedEndTranslation
                let distance = hypot(heading.width, heading.height)
                guard distance > Self.flingDistance else { return settle() }
                guard canSend else {
                    refusals += 1
                    return settle()
                }
                throwAway(towards: heading, distance: distance)
            }
    }

    private func settle() {
        withAnimation(.spring(duration: 0.45, bounce: 0.35)) {
            offset = .zero
            isLifted = false
        }
    }

    /// Off the screen in the direction it was thrown, then back in its place: it's a copy that went to the Mac.
    private func throwAway(towards heading: CGSize, distance: CGFloat) {
        let scale = 1400 / max(distance, 1)
        onSend()
        withAnimation(.easeIn(duration: 0.32)) {
            offset = CGSize(width: heading.width * scale, height: heading.height * scale)
            isGone = true
        }
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            var instantly = Transaction()
            instantly.disablesAnimations = true
            withTransaction(instantly) {
                offset = .zero
                isLifted = false
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) { isGone = false }
        }
    }
}
