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
            GlowBorder(intensity: model.pairedMac == nil ? 0 : model.glowIntensity)
        }
        .animation(.smooth(duration: 0.5), value: model.pairedMac == nil)
        .sensoryFeedback(.success, trigger: model.arrivals)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.departures)
    }
}
