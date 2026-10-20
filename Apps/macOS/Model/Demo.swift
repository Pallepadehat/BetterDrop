#if DEBUG
import BetterDropCore
import Foundation

/// Lets you try things without clicking, in debug builds. Run with `BETTERDROP_DEMO` set to any of:
///
///     accept   accept a pairing request after a couple of seconds (long enough to see the prompt)
///     send     send the newest file to a phone when it connects
extension MacModel {
    static let demo = Set((ProcessInfo.processInfo.environment["BETTERDROP_DEMO"] ?? "").split(separator: ",").map(String.init))

    func runDemoOnPairingRequest() {
        guard Self.demo.contains("accept") else { return }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            answerPairing(true)
        }
    }

    func runDemoOnConnect() {
        guard Self.demo.contains("send"), let item = library.items.first else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            send(item)
        }
    }
}
#endif
