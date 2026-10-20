import AppKit
import BetterDropCore
import BetterDropUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// What opens from the menu bar: who's connected, and every file, in the same cards as on the phone.
struct LibraryPanel: View {
    @Environment(MacModel.self) private var model
    @State private var preview: URL?
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Header()
            if let error = model.lastError {
                ErrorBanner(message: error) { model.dismissError() }
            }
            ScrollView {
                if model.library.items.isEmpty && model.incoming.isEmpty {
                    EmptyState()
                } else {
                    MasonryLayout(columns: 3, spacing: 10) {
                        ForEach(model.incoming) { transfer in
                            IncomingCard(transfer: transfer)
                        }
                        ForEach(model.library.items) { item in
                            card(for: item)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .animation(.spring(duration: 0.5, bounce: 0.25), value: model.library.items)
                }
            }
            .scrollIndicators(.never)
            .overlay {
                if isTargeted { DropHighlight(connected: model.isConnected) }
            }
            .dropDestination(for: URL.self) { urls, _ in
                take(urls)
                return true
            } isTargeted: { isTargeted = $0 }
            Footer()
        }
        .frame(width: 420, height: 600)
        .background(Glow.ink.opacity(0.55))
        .environment(\.colorScheme, .dark)
        .quickLookPreview($preview, in: model.library.items.map { model.library.url(for: $0) })
        .onAppear { model.library.refresh() }
    }

    private func card(for item: DropItem) -> some View {
        let url = model.library.url(for: item)
        return DropCard(item: item, url: url, progress: model.progress(for: item))
            .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
            .onTapGesture { preview = url }
            .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
            .contextMenu { ItemMenu(item: item, url: url, preview: $preview) }
            .transition(.blurReplace)
    }

    /// Dropped onto the panel: straight to the phone when there is one, otherwise into the library.
    private func take(_ urls: [URL]) {
        if model.isConnected {
            model.send(urls)
        } else {
            Task { for url in urls { try? await model.library.add(fileAt: url) } }
        }
    }
}

private struct Header: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Wordmark(size: 16, isLit: model.isConnected)
            Spacer()
            HStack(spacing: 6) {
                if let phone = model.currentPhone {
                    Image(systemName: phone.kind.symbolName)
                    Text(phone.name).lineLimit(1)
                } else {
                    Text(model.pairedDevices.isEmpty ? "No iPhone yet" : "iPhone not nearby")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .help(model.isConnected ? "Drag files to the edge of your screen to send them." : "Open BetterDrop on your iPhone and hold it next to your Mac.")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

/// Before anything's here: how it works, around a sleepy orb.
private struct EmptyState: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            LightOrb(energy: model.isConnected ? 0.6 : 0.2,
                     lean: CGVector(dx: model.preferences.side == .right ? 0.4 : -0.4, dy: 0))
                .frame(width: 150, height: 150)
            Text(model.pairedDevices.isEmpty ? "Bring your iPhone over" : "Nothing here yet")
                .font(.brand(20, weight: .semibold))
            Text(model.pairedDevices.isEmpty
                 ? "Open BetterDrop on your iPhone and hold it against the \(model.preferences.side == .right ? "right" : "left") side of your screen."
                 : "Throw a file off your iPhone towards the Mac, or drop files here or on the edge of the screen to send them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

private struct Footer: View {
    @Environment(MacModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 14) {
            Text("\(model.library.items.count) items · \(model.library.totalByteCount.fileSize)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Spacer()
            Button("Add Files…", systemImage: "plus", action: addFiles)
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.open(model.library.directory)
            }
            Menu {
                Button("Settings…") {
                    NSApp.activate()
                    openSettings()
                }
                .keyboardShortcut(",")
                Button("Check for Updates…") { Updates.shared.checkNow() }
                Divider()
                Button("Quit BetterDrop") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.white.opacity(0.04))
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = model.isConnected ? String(localized: "Send") : String(localized: "Add")
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        if model.isConnected {
            model.send(panel.urls)
        } else {
            Task { for url in panel.urls { try? await model.library.add(fileAt: url) } }
        }
    }
}

private struct ItemMenu: View {
    @Environment(MacModel.self) private var model
    let item: DropItem
    let url: URL
    @Binding var preview: URL?

    var body: some View {
        Button("Open", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
        Button("Quick Look", systemImage: "eye") { preview = url }
        Button(model.currentPhone.map { "Send to \($0.name)" } ?? "Send to iPhone", systemImage: "iphone.and.arrow.forward") {
            model.send(item)
        }
        .disabled(!model.isConnected)
        Divider()
        Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Button("Copy", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        }
        Divider()
        Button("Move to Trash", systemImage: "trash", role: .destructive) {
            NSWorkspace.shared.recycle([url]) { _, _ in
                Task { @MainActor in model.library.refresh() }
            }
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .transition(.blurReplace)
    }
}

private struct DropHighlight: View {
    let connected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.45))
            EdgeGlow(intensity: 0.9, cornerRadius: 18)
            VStack(spacing: 8) {
                Image(systemName: connected ? "iphone.and.arrow.forward" : "plus")
                    .font(.system(size: 30, weight: .light))
                    .glowingForeground()
                Text(connected ? "Drop to send to your iPhone" : "Drop to add to BetterDrop")
                    .font(.brand(16, weight: .semibold))
            }
        }
        .padding(8)
        .allowsHitTesting(false)
    }
}
