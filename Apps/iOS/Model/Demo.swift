#if DEBUG
import BetterDropCore
import Foundation

/// Lets you try things without touching the screen, in debug builds. Run with `BETTERDROP_DEMO` set to any of:
///
///     pair   press and hold Connect for you as soon as a Mac shows up
///     send   send the newest file once connected
///
/// From the terminal: `SIMCTL_CHILD_BETTERDROP_DEMO=pair,send xcrun simctl launch booted com.patrickjakobsen.betterdrop`
extension PhoneModel {
    func runDemo() {
        let demo = Set((ProcessInfo.processInfo.environment["BETTERDROP_DEMO"] ?? "").split(separator: ",").map(String.init))
        guard !demo.isEmpty else { return }
        Task {
            if demo.contains("pair") {
                while pairedMac == nil {
                    if let mac = candidateMac, pairing == .idle { await pair(with: mac) }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            if demo.contains("send") {
                while !isConnected { try? await Task.sleep(for: .milliseconds(300)) }
                try? await Task.sleep(for: .seconds(1))
                if let item = library.items.first { send(item) }
            }
        }
    }
}
#endif
