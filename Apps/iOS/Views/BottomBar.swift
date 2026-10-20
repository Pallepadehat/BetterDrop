import BetterDropCore
import BetterDropUI
import SwiftUI

/// The floating glass bar at the bottom: the Mac, adding files, how many there are, and more.
struct BottomBar: View {
    @Environment(PhoneModel.self) private var model
    let pickPhotos: () -> Void
    let importFiles: () -> Void
    let showSettings: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: showSettings) {
                    Image(systemName: "laptopcomputer")
                        .overlay(alignment: .topTrailing) {
                            Circle()
                                .fill(model.isConnected ? .green : .gray)
                                .frame(width: 8, height: 8)
                                .shadow(color: model.isConnected ? .green : .clear, radius: 3)
                                .offset(x: 5, y: -3)
                        }
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(model.isConnected ? "Connected to \(model.pairedMac?.device.name ?? "Mac")" : "Not connected")

                Menu {
                    Button("Photos & Videos", systemImage: "photo.on.rectangle", action: pickPhotos)
                    Button("Files", systemImage: "folder", action: importFiles)
                    Button("Paste", systemImage: "doc.on.clipboard") { Task { await paste() } }
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Add")

                Spacer(minLength: 0)

                Text("\(model.library.items.count) items")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.default, value: model.library.items.count)

                Spacer(minLength: 0)

                Menu {
                    Button("Settings", systemImage: "gearshape", action: showSettings)
                    Divider()
                    Button("Delete All", systemImage: "trash", role: .destructive) {
                        withAnimation { model.library.removeAll() }
                    }
                    .disabled(model.library.items.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("More")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    /// Whatever's on the clipboard becomes a file: pictures as PNG, text as a .txt.
    private func paste() async {
        let pasteboard = UIPasteboard.general
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(.dateTime.year().month().day().hour().minute().second()).replacingOccurrences(of: "/", with: "-")
        var url: URL?
        if let image = pasteboard.image, let data = image.pngData() {
            url = folder.appending(path: "Pasted Image \(stamp).png")
            try? data.write(to: url!)
        } else if let text = pasteboard.string {
            url = folder.appending(path: "Pasted Text \(stamp).txt")
            try? Data(text.utf8).write(to: url!)
        }
        if let url { await model.add([url], move: true) } else { model.lastError = String(localized: "There's nothing to paste.") }
    }
}
