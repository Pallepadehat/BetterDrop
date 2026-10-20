import SwiftUI

/// The big round button you press and hold to connect. A ring of light fills while you hold it; let go early and it
/// drains away. Holding (rather than tapping) means a phone in a pocket never pairs by accident.
public struct HoldToConnectButton: View {
    public var duration: Duration
    public var isEnabled: Bool
    public var action: () -> Void

    @State private var isPressing = false
    @State private var progress: Double = 0
    @State private var completions = 0

    public init(duration: Duration = .seconds(1.2), isEnabled: Bool = true, action: @escaping () -> Void) {
        self.duration = duration
        self.isEnabled = isEnabled
        self.action = action
    }

    private var seconds: Double { Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18 }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: Glow.colors + [Glow.colors[0]], center: .center),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Glow.colors[6].opacity(0.8), radius: 8)
            Circle()
                .fill(.white)
                .padding(12)
                .shadow(color: .white.opacity(isPressing ? 0.6 : 0.25), radius: isPressing ? 24 : 10)
            Image(systemName: "wave.3.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.black.opacity(0.55))
                .symbolEffect(.variableColor.iterative, isActive: isPressing)
        }
        .frame(width: 128, height: 128)
        .scaleEffect(isPressing ? 0.93 : 1)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.spring(duration: 0.3), value: isPressing)
        .contentShape(.circle)
        .onLongPressGesture(minimumDuration: seconds, maximumDistance: 40) {
            completions += 1
            withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            action()
        } onPressingChanged: { pressing in
            guard isEnabled else { return }
            isPressing = pressing
            withAnimation(pressing ? .linear(duration: seconds) : .easeOut(duration: 0.35)) {
                progress = pressing ? 1 : 0
            }
        }
        .disabled(!isEnabled)
        .sensoryFeedback(.impact(weight: .light), trigger: isPressing) { _, pressing in pressing }
        .sensoryFeedback(.success, trigger: completions)
        .accessibilityLabel(Text("Connect"))
        .accessibilityHint(Text("Press and hold to connect."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

#Preview {
    HoldToConnectButton {}
        .padding(60)
        .background(.black)
}
