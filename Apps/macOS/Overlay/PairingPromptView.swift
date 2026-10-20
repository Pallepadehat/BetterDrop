import BetterDropCore
import BetterDropTransport
import BetterDropUI
import SwiftUI

/// "Patrick's iPhone wants to connect": the code to compare, and the buttons.
struct PairingPromptView: View {
    let model: MacModel

    var body: some View {
        if let approval = model.pendingApproval {
            VStack(spacing: 18) {
                Image(systemName: approval.device.kind.symbolName)
                    .font(.system(size: 40, weight: .light))
                    .glowingForeground()
                    .symbolEffect(.pulse)
                VStack(spacing: 4) {
                    Text(approval.device.name)
                        .font(.title3.weight(.semibold))
                        .glowingForeground()
                    Text("wants to connect to this Mac")
                        .foregroundStyle(.secondary)
                }
                PairingCodeView(code: approval.code)
                    .scaleEffect(0.8)
                Text("Check the same code is on your iPhone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Decline", role: .cancel) { model.answerPairing(false) }
                        .keyboardShortcut(.cancelAction)
                    Button("Accept") { model.answerPairing(true) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.glassProminent)
                }
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
            .environment(\.colorScheme, .dark)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }
}
