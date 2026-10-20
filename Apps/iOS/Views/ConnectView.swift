import BetterDropCore
import BetterDropTransport
import BetterDropUI
import SwiftUI

/// "Hold iPhone next to Patrick's MacBook Pro. Then press and hold Connect." The screen edge glows brighter the
/// closer the Mac is.
struct ConnectView: View {
    @Environment(PhoneModel.self) private var model
    @State private var chosen: DiscoveredDevice?

    private var mac: DiscoveredDevice? { chosen.flatMap { c in model.browser.devices.first { $0.id == c.id } } ?? model.candidateMac }

    private var proximity: Proximity { mac.map(model.proximity(of:)) ?? .away }

    /// 0 to 1: how close the Mac is. Without Bluetooth, a steady middle so the screen still feels alive.
    private var closeness: Double {
        guard let mac else { return 0 }
        return model.measuresProximity ? model.closeness(of: mac) : 0.5
    }

    private var glow: Double {
        switch model.pairing {
        case .connecting, .confirming: return 1
        case .failed: return 0.25
        case .idle: break
        }
        guard mac != nil else { return 0.12 }
        return 0.18 + 0.82 * closeness
    }

    @State private var pulses = 0
    @State private var connectBursts = 0
    @State private var buttonCenter = CGPoint.zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AuroraBackground(intensity: mac == nil ? 0 : closeness)
                SonarRings(intensity: mac == nil || model.pairing != .idle ? 0 : 0.25 + 0.75 * closeness,
                           center: UnitPoint(x: buttonCenter.x / max(proxy.size.width, 1), y: buttonCenter.y / max(proxy.size.height, 1)),
                           reach: 0.75, lineWidth: 2)
                    .ignoresSafeArea()
                content
            }
            .edgeWarp(side: model.macSide, closeness: model.pairing == .idle ? closeness : 0)
            .ripple(at: model.macSide.origin(in: proxy.size), trigger: pulses, amplitude: 10)
            .ripple(at: buttonCenter, trigger: connectBursts, amplitude: 22, duration: 3)
            .overlay {
                GlowBorder(intensity: glow, emphasis: model.macSide == .left ? .leading : .trailing)
            }
            .background(.black)
        }
        .ignoresSafeArea()
        .animation(.smooth, value: model.pairing)
        .animation(.smooth, value: mac?.id)
        .animation(.smooth(duration: 0.4), value: closeness)
        // A soft tap each time you get a step closer.
        .sensoryFeedback(trigger: proximity) { old, new in
            new > old ? .impact(flexibility: .soft, intensity: new == .touching ? 1 : 0.5) : nil
        }
        .onChange(of: model.pairing) { _, pairing in
            if case .confirming = pairing { connectBursts += 1 }
        }
        // While the phone touches the Mac, the screen ripples from the Mac's side, like light coming through.
        .task(id: proximity == .touching && model.pairing == .idle) {
            guard proximity == .touching, model.pairing == .idle else { return }
            while !Task.isCancelled {
                pulses += 1
                try? await Task.sleep(for: .seconds(1.8))
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            heading
                .padding(.top, 120)
            Spacer()
            center
                .onGeometryChange(for: CGPoint.self) { proxy in
                    let frame = proxy.frame(in: .named("connect"))
                    return CGPoint(x: frame.midX, y: frame.midY)
                } action: { buttonCenter = $0 }
            Spacer()
            footer
                .padding(.bottom, 60)
        }
        .padding(.horizontal, 28)
        .coordinateSpace(.named("connect"))
    }

    @ViewBuilder private var heading: some View {
        VStack(spacing: 6) {
            if let mac {
                Text("Hold \(model.device.kind == .iPad ? "iPad" : "iPhone") next to")
                    .font(.title3.weight(.semibold))
                Text(mac.info.name)
                    .font(.largeTitle.weight(.bold))
                    .glowingForeground()
                    .shadow(color: Glow.colors[6].opacity(0.4 + 0.6 * closeness), radius: 6 + 14 * closeness)
                    .scaleEffect(1 + 0.04 * closeness)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .contentTransition(.opacity)
                Text("Then press and hold Connect.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Looking for your Mac…")
                    .font(.title2.weight(.semibold))
                Text("Open BetterDrop on your Mac. Both need to be on the same Wi-Fi.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let problem = model.browser.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private var center: some View {
        switch model.pairing {
        case .idle:
            HoldToConnectButton(isEnabled: mac != nil) {
                guard let mac else { return }
                Task { await model.pair(with: mac) }
            }
            .overlay(alignment: .bottom) {
                if mac != nil, model.measuresProximity, proximity < .touching {
                    Text("Move a little closer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(y: 40)
                        .transition(.opacity)
                }
            }
        case .connecting:
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        case let .confirming(code):
            VStack(spacing: 18) {
                PairingCodeView(code: code)
                Text("Click Accept on your Mac if it shows the same code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .transition(.scale.combined(with: .opacity))
        case let .failed(message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text(message)
                    .multilineTextAlignment(.center)
                Button("Try Again") { model.resetPairing() }
                    .buttonStyle(.glassProminent)
            }
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder private var footer: some View {
        let devices = model.browser.devices
        if devices.count > 1, model.pairing == .idle {
            Menu {
                ForEach(devices) { device in
                    Button(device.info.name, systemImage: device.info.kind.symbolName) { chosen = device }
                }
            } label: {
                Label("Not this Mac?", systemImage: "laptopcomputer")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        } else if mac != nil, !model.measuresProximity, model.pairing == .idle {
            Text("Bluetooth is off, so BetterDrop can't tell how close you are. Press and hold anyway.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
