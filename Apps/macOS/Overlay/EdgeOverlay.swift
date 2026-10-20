import AppKit
import BetterDropUI
import SwiftUI

/// The light at the edge of the screen, and the strip you drag files onto to send them.
///
/// Three borderless panels on the screen with the menu bar, at the edge you chose in Settings: the bloom (clicks go
/// straight through it), a thin strip right at the edge that catches dragged files while a phone is connected, and
/// the pairing prompt when a new phone asks to connect.
final class EdgeOverlay {
    private let model: MacModel
    private let bloomPanel: NSPanel
    private let dropPanel: NSPanel
    private let promptPanel: NSPanel
    private var observer: (any NSObjectProtocol)?

    /// How far into the screen the bloom reaches, as a share of the screen's height.
    private static let bloomDepth: CGFloat = 0.62
    private static let dropStripWidth: CGFloat = 10
    private static let promptSize = CGSize(width: 360, height: 300)

    init(model: MacModel) {
        self.model = model
        bloomPanel = Self.makePanel(ignoresMouse: true)
        bloomPanel.contentView = NSHostingView(rootView: EdgeOverlayView(model: model))
        dropPanel = Self.makePanel(ignoresMouse: false)
        dropPanel.contentView = NSHostingView(rootView: DropStrip(model: model))
        promptPanel = Self.makePanel(ignoresMouse: false)
        promptPanel.contentView = NSHostingView(rootView: PairingPromptView(model: model))
    }

    func start() {
        layout()
        bloomPanel.orderFrontRegardless()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        track()
    }

    /// Follows the model: shows the drop strip while a phone is connected, the prompt while one asks to pair, and
    /// moves everything when the edge changes.
    private func track() {
        withObservationTracking {
            _ = model.isConnected
            _ = model.pendingApproval
            _ = model.preferences.edge
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
        let trailing = model.preferences.edge == .trailing
        let depth = frame.height * Self.bloomDepth
        bloomPanel.setFrame(NSRect(x: trailing ? frame.maxX - depth : frame.minX, y: frame.minY, width: depth, height: frame.height),
                            display: true)

        let visible = screen.visibleFrame
        dropPanel.setFrame(NSRect(x: trailing ? frame.maxX - Self.dropStripWidth : frame.minX, y: visible.minY,
                                  width: Self.dropStripWidth, height: visible.height), display: true)
        if model.isConnected { dropPanel.orderFrontRegardless() } else { dropPanel.orderOut(nil) }

        let size = Self.promptSize
        let x = trailing ? visible.maxX - size.width - 48 : visible.minX + 48
        promptPanel.setFrame(NSRect(x: x, y: visible.midY - size.height / 2, width: size.width, height: size.height), display: true)
        if model.pendingApproval != nil {
            promptPanel.makeKeyAndOrderFront(nil)
        } else {
            promptPanel.orderOut(nil)
        }
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
