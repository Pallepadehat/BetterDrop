import BetterDropCore
import BetterDropTransport
import SwiftUI
import UIKit

@main
struct BetterDropApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = PhoneModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Bluetooth and the live connection only run while you're looking; big files carry on regardless.
                    if phase == .active { model.resume() } else if phase == .background { model.suspend() }
                }
        }
    }
}

/// Things that outlive the screen: the background transfer session iOS wakes us up for.
enum Services {
    static let pairings: any PairingStore = KeychainPairingStore()
    static let background = BackgroundTransfers(identifier: "com.patrickjakobsen.betterdrop.transfers", store: pairings)
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// iOS relaunched us in the background because transfers finished: let it know when we've dealt with them.
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        let done = UncheckedSendable(completionHandler)
        Services.background.setBackgroundCompletionHandler { done.value() }
    }
}

/// UIKit's completion handlers predate Sendable; this one is only ever called on the main queue.
private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
