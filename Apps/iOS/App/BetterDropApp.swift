import SwiftUI

@main
struct BetterDropApp: App {
    @State private var model = PhoneModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Bluetooth scanning and the connection only run while you're looking at the app.
                    if phase == .active { model.resume() } else if phase == .background { model.suspend() }
                }
        }
    }
}
