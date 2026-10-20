import BetterDropCore
import BetterDropTransport
import BetterDropUI
import SwiftUI

/// The first thing you see: a drop of light that wakes up and leans towards your Mac as you bring the phone to it.
/// Press and hold it to connect; it charges, then bursts into a ripple and shows the code to compare.
struct ConnectView: View {
    @Environment(PhoneModel.self) private var model
    @State private var chosen: DiscoveredDevice?
    @State private var isHolding = false
    @State private var charge: Double = 0
    @State private var holdTicks = 0
    @State private var bursts = 0
    @State private var pulses = 0

    private static let holdDuration = 1.3

    private var mac: DiscoveredDevice? {
        chosen.flatMap { chosen in model.browser.devices.first { $0.id == chosen.id } } ?? model.candidateMac
    }

    private var proximity: Proximity { mac.map(model.proximity(of:)) ?? .away }

    /// 0 to 1. Without Bluetooth, a steady middle so the screen still feels alive.
    private var closeness: Double {
        guard let mac else { return 0 }
        return model.measuresProximity ? model.closeness(of: mac) : 0.55
    }

    private var isPairing: Bool { model.pairing != .idle && !model.pairing.isFailure }

    private var energy: Double {
        if isPairing { return 1 }
        return mac == nil ? 0.12 : 0.25 + 0.75 * closeness
    }

    /// Reaches towards the Mac's side as it gets closer.
    private var lean: CGVector {
        guard mac != nil, !isPairing else { return .zero }
        let reach = pow(closeness, 1.4) * 0.9
        return CGVector(dx: model.macEdge == .leading ? -reach : reach, dy: 0)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                light(in: proxy.size)
                chrome(insets: proxy.safeAreaInsets)
            }
            .overlay { EdgeGlow(intensity: isPairing ? 0.9 : 0.1 + 0.8 * closeness, emphasis: mac == nil ? nil : model.macEdge, surge: bursts) }
            .background(.black)
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.8), value: isPairing)
        .animation(.smooth(duration: 0.5), value: closeness)
        .animation(.smooth(duration: 0.6), value: model.pairing)
        .animation(.smooth(duration: 0.6), value: mac?.id)
        .sensoryFeedback(trigger: proximity, Self.nearerFeedback)
        .sensoryFeedback(trigger: holdTicks, Self.holdFeedback)
        .sensoryFeedback(.success, trigger: bursts)
        .task(id: isHolding) { await patter() }
        .task(id: proximity == .touching && model.pairing == .idle) { await pulseWhileTouching() }
    }

    private func orbCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * (isPairing ? 0.34 : 0.43))
    }

    /// The aurora and the orb. Only these ripple: the words and buttons stay put.
    private func light(in size: CGSize) -> some View {
        let center = orbCenter(in: size)
        let orbSize = size.width * (isPairing ? 0.62 : 0.86)
        let edgePoint = CGPoint(x: model.macEdge == .leading ? 0 : size.width, y: center.y)
        return ZStack {
            AuroraBackground(intensity: mac == nil ? 0.05 : closeness * 0.9)
            LightOrb(energy: energy, lean: lean, charge: charge)
                .frame(width: orbSize, height: orbSize)
                .position(center)
            Circle()
                .fill(.clear)
                .contentShape(.circle)
                .frame(width: orbSize * 0.5, height: orbSize * 0.5)
                .position(center)
                .onLongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: 60, perform: connect, onPressingChanged: holding)
                .accessibilityElement()
                .accessibilityLabel("Connect")
                .accessibilityHint("Press and hold to connect to your Mac.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { connect() }
        }
        .ripple(at: edgePoint, trigger: pulses, amplitude: 9)
        .ripple(at: center, trigger: bursts, amplitude: 24, duration: 3)
    }

    private func chrome(insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            Wordmark(size: 17, isLit: mac != nil)
                .foregroundStyle(.white)
                .padding(.top, insets.top + 18)
            Spacer()
            caption
                .frame(maxWidth: 330)
                .padding(.bottom, insets.bottom + 40)
        }
        .frame(maxWidth: .infinity)
    }

    private static func nearerFeedback(_ old: Proximity, _ new: Proximity) -> SensoryFeedback? {
        new > old ? .impact(flexibility: .soft, intensity: new == .touching ? 1 : 0.5) : nil
    }

    private static func holdFeedback(_ old: Int, _ ticks: Int) -> SensoryFeedback? {
        ticks > 0 ? .impact(flexibility: .rigid, intensity: min(1, 0.2 + Double(ticks) * 0.08)) : nil
    }

    /// A rising patter while you hold, faster towards the end.
    private func patter() async {
        guard isHolding else { return }
        var interval = 0.16
        while !Task.isCancelled {
            holdTicks += 1
            try? await Task.sleep(for: .seconds(interval))
            interval = max(0.05, interval * 0.88)
        }
    }

    /// Touching the Mac, the light ripples in from its side, as if it were shining through.
    private func pulseWhileTouching() async {
        guard proximity == .touching, model.pairing == .idle else { return }
        while !Task.isCancelled {
            pulses += 1
            try? await Task.sleep(for: .seconds(2.2))
        }
    }

    // MARK: - Holding

    private func holding(_ pressing: Bool) {
        guard mac != nil, !isPairing else { return }
        isHolding = pressing
        if !pressing { holdTicks = 0 }
        withAnimation(pressing ? .linear(duration: Self.holdDuration) : .spring(duration: 0.6, bounce: 0.4)) {
            charge = pressing ? 1 : 0
        }
    }

    private func connect() {
        guard let mac, !isPairing else { return }
        isHolding = false
        bursts += 1
        withAnimation(.spring(duration: 0.8, bounce: 0.5)) { charge = 0 }
        Task { await model.pair(with: mac) }
    }

    // MARK: - Words

    @ViewBuilder private var caption: some View {
        VStack(spacing: 10) {
            switch model.pairing {
            case .idle:
                if let mac {
                    Text(closeness > 0.7 || !model.measuresProximity ? "Hold the light to connect to" : "Bring your iPhone to")
                        .font(.brand(17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .contentTransition(.interpolate)
                    Text(mac.info.name)
                        .font(.brand(30, weight: .bold))
                        .glowingForeground()
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.interpolate)
                    otherMacs
                } else {
                    Text("Looking for your Mac")
                        .font(.brand(26, weight: .bold))
                        .foregroundStyle(.white)
                    Text(model.browser.problem ?? String(localized: "Open BetterDrop on your Mac. Both need to be on the same Wi-Fi."))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            case .connecting:
                Text("Reaching \(mac?.info.name ?? "your Mac")…")
                    .font(.brand(20, weight: .semibold))
                    .foregroundStyle(.white)
            case let .confirming(code):
                PairingCodeView(code: code, size: 30)
                Text("Accept on your Mac if it shows the same code.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            case let .failed(message):
                Text(message)
                    .font(.brand(18, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("Try Again") { model.resetPairing() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
        }
        .transition(.blurReplace)
    }

    @ViewBuilder private var otherMacs: some View {
        let devices = model.browser.devices
        if devices.count > 1 {
            Menu {
                ForEach(devices) { device in
                    Button(device.info.name, systemImage: device.info.kind.symbolName) { chosen = device }
                }
            } label: {
                Text("Not this Mac?")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.top, 6)
        } else if !model.measuresProximity {
            Text("Bluetooth is off, so BetterDrop can't tell how close you are.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
    }
}
