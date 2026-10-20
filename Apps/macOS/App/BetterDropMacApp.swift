import AppKit
import BetterDropCore
import BetterDropUI
import SwiftUI

@main
struct BetterDropMacApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            LibraryPanel()
                .environment(delegate.model)
        } label: {
            MenuBarIcon(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(delegate.model)
        }
    }
}

/// The menu bar icon: waves while a phone is connected, a phone when files are moving.
private struct MenuBarIcon: View {
    let model: MacModel

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel("BetterDrop")
    }

    private var symbol: String {
        if !model.transfers.isEmpty { return "iphone.radiowaves.left.and.right" }
        return model.isConnected ? "wave.3.right.circle.fill" : "wave.3.right.circle"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MacModel()
    private var overlay: EdgeOverlay?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        let overlay = EdgeOverlay(model: model)
        overlay.start()
        self.overlay = overlay
        Updates.shared.start()
    }
}
