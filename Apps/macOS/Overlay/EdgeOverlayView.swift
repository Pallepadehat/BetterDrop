import BetterDropCore
import BetterDropUI
import SwiftUI

/// The portal of light, and files condensing out of it as they arrive.
struct EdgeOverlayView: View {
    let model: MacModel

    var body: some View {
        ZStack {
            LightPortal(intensity: model.portalIntensity, waves: model.portalWaves, side: model.preferences.side, surge: model.surges)
                .animation(.smooth(duration: 0.4), value: model.portalIntensity)
                .animation(.smooth(duration: 0.6), value: model.portalWaves)
            ForEach(model.arrivals) { item in
                ArrivalCard(item: item, url: model.library.url(for: item), side: model.preferences.side) {
                    model.arrivals.removeAll { $0.id == item.id }
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// A file that just arrived: it condenses out of the light at the edge, floats for a moment so you can see what it
/// is, then drifts up to the menu bar, where the library lives.
private struct ArrivalCard: View {
    let item: DropItem
    let url: URL
    let side: Side
    let onLanded: () -> Void

    private enum Phase { case condensing, shown, leaving }
    @State private var phase = Phase.condensing
    @State private var burn: Double = 1

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let inward: CGFloat = side == .right ? -1 : 1
            let edgeX: CGFloat = side == .right ? size.width - 40 : 40
            let shownX = edgeX + inward * 230
            DropCard(item: item, url: url)
                .frame(width: 210)
                .lightDissolve(burn, towards: CGVector(dx: inward, dy: 0))
                .shadow(color: .black.opacity(0.4), radius: 30, y: 14)
                .rotation3DEffect(.degrees(phase == .condensing ? Double(inward) * -35 : 0), axis: (x: 0, y: 1, z: 0))
                .scaleEffect(phase == .leaving ? 0.25 : (phase == .condensing ? 0.85 : 1))
                .opacity(phase == .leaving ? 0 : 1)
                .position(x: phase == .condensing ? edgeX + inward * 120 : shownX,
                          y: phase == .leaving ? -60 : size.height * 0.5)
                .environment(\.colorScheme, .dark)
        }
        .task {
            withAnimation(.spring(duration: 0.9, bounce: 0.25)) { phase = .shown }
            withAnimation(.easeOut(duration: 1.0)) { burn = 0 }
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeIn(duration: 0.6)) { phase = .leaving }
            try? await Task.sleep(for: .seconds(0.65))
            onLanded()
        }
    }
}
