import AppKit
import BetterDropCore
import BetterDropUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// What opens from the menu bar: who's connected, and every file, in the same grid as on the phone.
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
                if model.library.items.isEmpty && incoming.isEmpty {
                    EmptyLibraryView(message: "Hold your iPhone next to your Mac and fling a file off its screen, or drop files here to send them.")
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    MasonryLayout(columns: 3, spacing: 12) {
                        ForEach(incoming) { transfer in
                            IncomingCard(transfer: transfer)
                        }
                        ForEach(model.library.items) { item in
                            card(for: item)
                        }
                    }
                    .padding(14)
                    .animation(.spring(duration: 0.45, bounce: 0.25), value: model.library.items)
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
        .frame(width: 400, height: 580)
        .quickLookPreview($preview, in: model.library.items.map { model.library.url(for: $0) })
        .onAppear { model.library.refresh() }
    }

    private var incoming: [Transfer] {
        model.transfers.values.filter { $0.direction == .incoming }.sorted { $0.name < $1.name }
    }

    private func card(for item: DropItem) -> some View {
        let url = model.library.url(for: item)
        return ItemCard(item: item, url: url, progress: model.progress(for: item)) {
            ItemMenu(item: item, url: url, preview: $preview)
        }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onTapGesture { preview = url }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu { ItemMenu(item: item, url: url, preview: $preview) }
        .transition(.scale(scale: 0.6).combined(with: .opacity))
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
            Image(systemName: "sparkles")
                .font(.title3)
                .glowingForeground()
            Text("BetterDrop")
                .font(.headline)
            Spacer()
            ConnectionPill()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct ConnectionPill: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.isConnected ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
                .shadow(color: model.isConnected ? .green : .clear, radius: 4)
            if let phone = model.currentPhone {
                Image(systemName: phone.kind.symbolName)
                Text(phone.name).lineLimit(1)
            } else {
                Text(model.pairedDevices.isEmpty ? "No iPhone yet" : "Waiting for iPhone")
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
        .help(model.isConnected ? "Drag files to the edge of your screen to send them." : "Open BetterDrop on your iPhone and hold it next to your Mac.")
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
        .padding(.vertical, 10)
        .background(.bar)
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
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
        .padding(.horizontal, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

private struct DropHighlight: View {
    let connected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.35))
            GlowBorder(intensity: 1, cornerRadius: 16)
            Label(connected ? "Drop to send to your iPhone" : "Drop to add to BetterDrop",
                  systemImage: connected ? "iphone.and.arrow.forward" : "plus")
                .font(.headline)
                .foregroundStyle(.white)
        }
        .padding(8)
        .allowsHitTesting(false)
    }
}
