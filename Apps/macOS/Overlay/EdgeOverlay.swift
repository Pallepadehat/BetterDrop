import AppKit
import BetterDropCore
import SwiftUI

/// The light at the edge of the screen, and the strip you drag files onto to send them.
///
/// Three borderless panels on the screen with the menu bar, at the side the phone sits: the light (clicks go
/// straight through it), a thin strip right at the edge that catches dragged files while a phone is connected, and
/// the pairing prompt. The light's panel is taken off screen whenever it's dark, so it costs nothing at rest.
final class EdgeOverlay {
    private let model: MacModel
    private let lightPanel: NSPanel
    private let dropPanel: NSPanel
    private let promptPanel: NSPanel
    private var observer: (any NSObjectProtocol)?
    private var litUntil = Date.distantPast
    private var lastSurge = 0

    /// How far into the screen the light reaches, as a share of the screen's height.
    private static let lightDepth: CGFloat = 0.7
    private static let dropStripWidth: CGFloat = 10
    private static let promptSize = CGSize(width: 380, height: 360)

    init(model: MacModel) {
        self.model = model
        lightPanel = Self.makePanel(ignoresMouse: true)
        lightPanel.contentView = NSHostingView(rootView: EdgeOverlayView(model: model))
        dropPanel = Self.makePanel(ignoresMouse: false)
        dropPanel.contentView = NSHostingView(rootView: DropStrip(model: model))
        promptPanel = Self.makePanel(ignoresMouse: false)
        promptPanel.contentView = NSHostingView(rootView: PairingPromptView(model: model))
    }

    func start() {
        layout()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        track()
    }

    /// Follows the model and lays the panels out again whenever something they depend on changes.
    private func track() {
        withObservationTracking {
            _ = model.isConnected
            _ = model.pendingApproval
            _ = model.preferences.side
            _ = model.portalIntensity
            _ = model.portalWaves
            _ = model.arrivals.count
            _ = model.surges
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.layout()
                self?.track()
            }
        }
    }

    private func layout() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        let right = model.preferences.side == .right
        let depth = frame.height * Self.lightDepth
        lightPanel.setFrame(NSRect(x: right ? frame.maxX - depth : frame.minX, y: frame.minY, width: depth, height: frame.height),
                            display: false)
        showLightIfNeeded()

        let visible = screen.visibleFrame
        dropPanel.setFrame(NSRect(x: right ? frame.maxX - Self.dropStripWidth : frame.minX, y: visible.minY,
                                  width: Self.dropStripWidth, height: visible.height), display: false)
        if model.isConnected { dropPanel.orderFrontRegardless() } else { dropPanel.orderOut(nil) }

        let size = Self.promptSize
        let x = right ? visible.maxX - size.width - 60 : visible.minX + 60
        promptPanel.setFrame(NSRect(x: x, y: visible.midY - size.height / 2, width: size.width, height: size.height), display: false)
        if model.pendingApproval != nil {
            promptPanel.makeKeyAndOrderFront(nil)
        } else {
            promptPanel.orderOut(nil)
        }
    }

    /// The light's panel is up while there's light, and for the length of a surge after the last one.
    private func showLightIfNeeded() {
        if model.surges != lastSurge {
            lastSurge = model.surges
            litUntil = .now.addingTimeInterval(1.7)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.8))
                self?.showLightIfNeeded()
            }
        }
        let lit = model.portalIntensity > 0.002 || model.portalWaves > 0.002 || !model.arrivals.isEmpty || litUntil > .now
        if lit { lightPanel.orderFrontRegardless() } else { lightPanel.orderOut(nil) }
    }

    private static func makePanel(ignoresMouse: Bool) -> NSPanel {
        let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = ignoresMouse
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }
}

/// Borderless panels can't become key by default, which the pairing prompt's buttons need for the keyboard.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
}

/// The strip at the very edge of the screen: drag files onto it and they fly to the phone.
private struct DropStrip: View {
    let model: MacModel

    var body: some View {
        Color.black.opacity(0.001)
            .dropDestination(for: URL.self) { urls, _ in
                model.send(urls)
                return !urls.isEmpty
            } isTargeted: { targeted in
                model.isDropTargeted = targeted
            }
    }
}
