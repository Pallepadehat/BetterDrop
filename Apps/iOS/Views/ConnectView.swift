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

    private var glow: Double {
        switch model.pairing {
        case .connecting, .confirming: return 1
        case .failed: return 0.25
        case .idle: break
        }
        guard mac != nil else { return 0.15 }
        guard model.measuresProximity else { return 0.6 }
        return switch proximity {
        case .touching: 1
        case .nearby: 0.5
        case .away: 0.2
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GlowBorder(intensity: glow)
            VStack(spacing: 0) {
                heading
                    .padding(.top, 70)
                Spacer()
                center
                Spacer()
                footer
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 28)
        }
        .animation(.smooth, value: model.pairing)
        .animation(.smooth, value: mac?.id)
    }

    @ViewBuilder private var heading: some View {
        VStack(spacing: 6) {
            if let mac {
                Text("Hold \(model.device.kind == .iPad ? "iPad" : "iPhone") next to")
                    .font(.title3.weight(.semibold))
                Text(mac.info.name)
                    .font(.largeTitle.weight(.bold))
                    .glowingForeground()
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
