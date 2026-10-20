import BetterDropCore
import BetterDropTransport
import BetterDropUI
import SwiftUI

/// "Patrick's iPhone wants to connect": a bright orb, the code to compare, and the buttons.
struct PairingPromptView: View {
    let model: MacModel

    var body: some View {
        ZStack {
            if let approval = model.pendingApproval {
                VStack(spacing: 16) {
                    LightOrb(energy: 0.9, lean: CGVector(dx: model.preferences.side == .right ? 0.5 : -0.5, dy: 0))
                        .frame(width: 120, height: 120)
                    VStack(spacing: 3) {
                        Text(approval.device.name)
                            .font(.brand(22, weight: .bold))
                            .glowingForeground()
                        Text("wants to connect to this Mac")
                            .foregroundStyle(.secondary)
                    }
                    PairingCodeView(code: approval.code, size: 24)
                    Text("Check the same code is on your iPhone.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Decline", role: .cancel) { model.answerPairing(false) }
                            .keyboardShortcut(.cancelAction)
                            .buttonStyle(.glass)
                        Button("Accept") { model.answerPairing(true) }
                            .keyboardShortcut(.defaultAction)
                            .buttonStyle(.glassProminent)
                    }
                    .controlSize(.large)
                }
                .padding(26)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(.regular, in: .rect(cornerRadius: 32, style: .continuous))
                .transition(.blurReplace)
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.spring(duration: 0.5), value: model.pendingApproval)
    }
}
