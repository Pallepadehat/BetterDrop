import BetterDropCore
import BetterDropUI
import PhotosUI
import QuickLook
import SwiftUI

/// Every file, in two columns like the Photos grid. Hold a card and fling it off the screen to send it to the Mac.
struct LibraryScreen: View {
    @Environment(PhoneModel.self) private var model
    @State private var preview: URL?
    @State private var pickingPhotos = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var importingFiles = false
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            if model.library.items.isEmpty && incoming.isEmpty {
                EmptyLibraryView(message: "Add photos, videos and files with +, then hold one and fling it off the screen to send it to your Mac.")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 160)
            } else {
                MasonryLayout(columns: 2, spacing: 12) {
                    ForEach(incoming) { transfer in
                        IncomingCard(transfer: transfer)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                    ForEach(model.library.items) { item in
                        card(for: item)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 110)
                .animation(.spring(duration: 0.5, bounce: 0.3), value: model.library.items)
                .animation(.spring(duration: 0.5, bounce: 0.3), value: incoming.map(\.id))
            }
        }
        .scrollIndicators(.hidden)
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) { StatusToast() }
        .safeAreaInset(edge: .bottom) {
            BottomBar(pickPhotos: { pickingPhotos = true }, importFiles: { importingFiles = true },
                      showSettings: { showingSettings = true })
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
    }

    private var incoming: [Transfer] {
        model.transfers.values.filter { $0.direction == .incoming }.sorted { $0.name < $1.name }
    }

    private func card(for item: DropItem) -> some View {
        let url = model.library.url(for: item)
        return FlingableCard(item: item, url: url, progress: model.progress(for: item), canSend: model.isConnected,
                             onSend: { model.send(item) }, onOpen: { preview = url }) {
            ItemActions(item: item, url: url)
        }
        .transition(.asymmetric(insertion: .scale(scale: 0.5).combined(with: .opacity).combined(with: .offset(y: -80)),
                                removal: .scale(scale: 0.8).combined(with: .opacity)))
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

/// A short message at the top: an error, or where you are with the Mac.
private struct StatusToast: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        Group {
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .onTapGesture { model.lastError = nil }
                    .task(id: error) {
                        try? await Task.sleep(for: .seconds(4))
                        model.lastError = nil
                    }
            } else if model.connection == .connecting {
                Label("Connecting to \(model.pairedMac?.device.name ?? "your Mac")…", systemImage: "laptopcomputer")
            }
        }
        .font(.footnote.weight(.medium))
        .lineLimit(2)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .padding(.top, 4)
        .padding(.horizontal, 20)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring, value: model.lastError)
        .animation(.spring, value: model.connection)
    }
}
