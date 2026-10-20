import BetterDropCore
import BetterDropUI
import SwiftUI

/// The bloom, and files flying in out of it as they arrive.
struct EdgeOverlayView: View {
    let model: MacModel

    var body: some View {
        ZStack {
            EdgeBloom(intensity: model.bloomIntensity, edge: model.preferences.edge)
            ForEach(model.arrivals) { item in
                ArrivalCard(item: item, url: model.library.url(for: item), edge: model.preferences.edge) {
                    model.arrivals.removeAll { $0.id == item.id }
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// A file that just arrived: it slides out of the edge, floats for a moment so you see what it is, then drifts up
/// towards the menu bar, where the library is.
private struct ArrivalCard: View {
    let item: DropItem
    let url: URL
    let edge: EdgeBloom.Edge
    let onLanded: () -> Void

    private enum Phase { case hidden, shown, leaving }
    @State private var phase = Phase.hidden

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let fromEdge: CGFloat = edge == .trailing ? size.width + 160 : -160
            let shownX: CGFloat = edge == .trailing ? size.width - 220 : 220
            ItemCard(item: item, url: url)
                .frame(width: 200)
                .padding(10)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                .environment(\.colorScheme, .dark)
                .rotationEffect(.degrees(phase == .hidden ? (edge == .trailing ? 14 : -14) : 0))
                .scaleEffect(phase == .shown ? 1 : (phase == .leaving ? 0.2 : 0.7))
                .opacity(phase == .leaving ? 0 : 1)
                .position(x: phase == .hidden ? fromEdge : shownX,
                          y: phase == .leaving ? -40 : size.height / 2)
        }
        .task {
            withAnimation(.spring(duration: 0.7, bounce: 0.3)) { phase = .shown }
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeIn(duration: 0.6)) { phase = .leaving }
            try? await Task.sleep(for: .seconds(0.65))
            onLanded()
        }
    }
}
