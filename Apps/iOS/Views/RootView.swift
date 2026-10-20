import BetterDropUI
import SwiftUI

/// Connect first; after that, the library. The edge light sits over everything.
struct RootView: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        ZStack {
            if model.pairedMac == nil {
                ConnectView()
                    .transition(.blurReplace)
            } else {
                LibraryScreen()
                    .transition(.blurReplace)
                EdgeGlow(intensity: model.edgeIntensity, emphasis: model.macEdge, surge: model.surges)
                    .animation(.smooth(duration: 0.35), value: model.edgeIntensity)
            }
        }
        .animation(.smooth(duration: 0.7), value: model.pairedMac == nil)
        .sensoryFeedback(.success, trigger: model.arrivals)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.departures)
    }
}
