import BetterDropCore
import BetterDropUI
import PhotosUI
import QuickLook
import SwiftUI

/// Every file, in two columns. Hold a card and throw it: it burns into light and flies to the Mac.
struct LibraryScreen: View {
    @Environment(PhoneModel.self) private var model
    @AppStorage("hasFlung") private var hasFlung = false
    @State private var preview: URL?
    @State private var pickingPhotos = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var importingFiles = false
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(showSettings: { showingSettings = true })
                if let hint {
                    Hint(text: hint)
                }
                if model.library.items.isEmpty && model.incoming.isEmpty {
                    EmptyLibraryView(message: "Add photos, videos and files with +. Then hold one and throw it towards your Mac.")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    grid
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(Glow.ink.ignoresSafeArea())
        .overlay(alignment: .top) { ErrorToast() }
        .safeAreaInset(edge: .bottom) {
            BottomBar(pickPhotos: { pickingPhotos = true }, importFiles: { importingFiles = true })
        }
        .refreshable { model.library.refresh() }
        .quickLookPreview($preview, in: model.library.items.map { model.library.url(for: $0) })
        .photosPicker(isPresented: $pickingPhotos, selection: $photoSelection, matching: .any(of: [.images, .videos]))
        .onChange(of: photoSelection) { _, selection in
            guard !selection.isEmpty else { return }
            photoSelection = []
            Task { await importPhotos(selection) }
        }
        .fileImporter(isPresented: $importingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            Task { await model.add(urls) }
        }
        .sheet(isPresented: $showingSettings) { SettingsSheet() }
        .onChange(of: model.departures) { hasFlung = true }
    }

    private var grid: some View {
        MasonryLayout(columns: 2, spacing: 10) {
            ForEach(model.incoming) { transfer in
                IncomingCard(transfer: transfer)
                    .transition(.blurReplace)
            }
            ForEach(model.library.items) { item in
                let url = model.library.url(for: item)
                FlingableCard(item: item, url: url, progress: model.progress(for: item), canSend: model.isConnected,
                              macEdge: model.macEdge, isFresh: model.freshItems.contains(item.id),
                              onSend: { model.send(item) }, onOpen: { preview = url },
                              onPull: { model.dragPull = $0 }, onSettled: { model.freshItems.remove(item.id) }) {
                    ItemActions(item: item, url: url)
                }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.55, bounce: 0.3), value: model.library.items)
        .animation(.spring(duration: 0.55, bounce: 0.3), value: model.incoming.map(\.id))
    }

    private var hint: String? {
        if model.backgroundTransferCount > 0 {
            return String(localized: "Big files keep going in the background. You can leave the app.")
        }
        if model.isConnected, !hasFlung, !model.library.items.isEmpty {
            return String(localized: "Hold a card and throw it towards your Mac.")
        }
        return nil
    }

    private func importPhotos(_ selection: [PhotosPickerItem]) async {
        for picked in selection {
            do {
                if let file = try await picked.loadTransferable(type: PickedFile.self) {
                    await model.add([file.url], move: true)
                }
            } catch {
                model.lastError = error.localizedDescription
            }
        }
    }
}

/// "Drops", and who we're connected to.
private struct Header: View {
    @Environment(PhoneModel.self) private var model
    let showSettings: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Text("Drops")
                .font(.brand(34, weight: .bold))
            Spacer()
            Button(action: showSettings) {
                HStack(spacing: 8) {
                    StatusOrb(isLit: model.isConnected)
                        .frame(width: 20, height: 20)
                    Text(status)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityLabel("Settings, \(status)")
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
    }

    private var status: String {
        let name = model.pairedMac?.device.name ?? String(localized: "Mac")
        return switch model.connection {
        case .connected: name
        case .connecting: String(localized: "Connecting…")
        case .idle: String(localized: "Not nearby")
        }
    }
}

private struct Hint: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "hand.draw")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Glow.text, lineWidth: 0.75).opacity(0.5))
            .transition(.blurReplace)
    }
}

/// The "…" menu on each card.
private struct ItemActions: View {
    @Environment(PhoneModel.self) private var model
    let item: DropItem
    let url: URL

    var body: some View {
        Button("Send to \(model.pairedMac?.device.name ?? "Mac")", systemImage: "laptopcomputer.and.arrow.down") {
            model.send(item)
        }
        .disabled(!model.isConnected)
        ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
        if item.kind.isVisual {
            Button("Save to Photos", systemImage: "photo.badge.plus") {
                Task { await model.saveToPhotos(item) }
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            withAnimation { model.library.remove(item) }
        }
    }
}

private struct ErrorToast: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        ZStack {
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .lineLimit(3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 20)
                    .onTapGesture { model.lastError = nil }
                    .task(id: error) {
                        try? await Task.sleep(for: .seconds(4))
                        model.lastError = nil
                    }
                    .transition(.move(edge: .top).combined(with: .blurReplace))
            }
        }
        .animation(.spring(duration: 0.5), value: model.lastError)
    }
}
