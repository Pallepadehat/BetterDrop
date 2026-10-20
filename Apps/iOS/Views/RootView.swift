import BetterDropUI
import SwiftUI

/// Connect first; after that, the library. The glow sits on top of everything, around the edge of the screen.
struct RootView: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        ZStack {
            if model.pairedMac == nil {
                ConnectView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else {
                LibraryScreen()
                    .transition(.opacity)
            }
            if model.pairedMac != nil {
                GlowBorder(intensity: model.glowIntensity, emphasis: model.macSide == .left ? .leading : .trailing)
                Shockwave(trigger: model.bursts, center: UnitPoint(x: model.macSide == .left ? 0 : 1, y: 0.45))
                    .ignoresSafeArea()
            }
        }
        .animation(.smooth(duration: 0.5), value: model.pairedMac == nil)
        .sensoryFeedback(.success, trigger: model.arrivals)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.departures)
    }
}
