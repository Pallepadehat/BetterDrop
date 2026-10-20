import BetterDropCore
import BetterDropUI
import SwiftUI
import UIKit

/// A floating glass bar: how many files, and adding more.
struct BottomBar: View {
    @Environment(PhoneModel.self) private var model
    let pickPhotos: () -> Void
    let importFiles: () -> Void
    @State private var confirmingClear = false

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                Menu {
                    Button("Delete All", systemImage: "trash", role: .destructive) { confirmingClear = true }
                        .disabled(model.library.items.isEmpty)
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(model.library.items.count) items")
                            .font(.footnote.weight(.semibold))
                            .contentTransition(.numericText())
                        Text(model.library.totalByteCount.fileSize)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .animation(.default, value: model.library.items.count)

                Spacer(minLength: 0)

                Button("Photos", systemImage: "photo.on.rectangle.angled", action: pickPhotos)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 54, height: 54)
                    .glassEffect(.regular.interactive(), in: .circle)

                Menu {
                    Button("Photos & Videos", systemImage: "photo.on.rectangle", action: pickPhotos)
                    Button("Files", systemImage: "folder", action: importFiles)
                    Button("Paste", systemImage: "doc.on.clipboard") { Task { await paste() } }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 54, height: 54)
                }
                .glassEffect(.regular.tint(Glow.colors[2].opacity(0.55)).interactive(), in: .circle)
                .accessibilityLabel("Add")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.bottom, 2)
        .confirmationDialog("Delete all \(model.library.items.count) files?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { withAnimation { model.library.removeAll() } }
        }
    }

    /// Whatever's on the clipboard becomes a file: pictures as PNG, text as a .txt.
    private func paste() async {
        let pasteboard = UIPasteboard.general
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: ".")
        let file: URL
        if let image = pasteboard.image, let data = image.pngData() {
            file = folder.appending(path: "Pasted Image \(stamp).png")
            try? data.write(to: file)
        } else if let text = pasteboard.string {
            file = folder.appending(path: "Pasted Text \(stamp).txt")
            try? Data(text.utf8).write(to: file)
        } else {
            model.lastError = String(localized: "There's nothing to paste.")
            return
        }
        await model.add([file], move: true)
    }
}
