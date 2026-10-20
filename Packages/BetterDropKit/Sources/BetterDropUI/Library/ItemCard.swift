import BetterDropCore
import SwiftUI

/// One file: pictures and videos fill their card edge to edge with the name over them, documents sit on a dark
/// glass card as a page.
public struct DropCard<Menu: View>: View {
    public var item: DropItem
    public var url: URL
    /// 0 to 1 while the file is on its way somewhere.
    public var progress: Double?
    /// Show the "…" menu in the corner. Turn it off while effects run over the card: platform menus can't be
    /// drawn into a shader.
    public var showsMenu: Bool
    private let menu: Menu

    public init(item: DropItem, url: URL, progress: Double? = nil, showsMenu: Bool = true, @ViewBuilder menu: () -> Menu) {
        self.item = item
        self.url = url
        self.progress = progress
        self.showsMenu = showsMenu
        self.menu = menu()
    }

    static var cornerRadius: CGFloat { 20 }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        Color.clear
            .aspectRatio(CardShape.ratio(for: item.kind, aspectRatio: item.aspectRatio), contentMode: .fit)
            .overlay {
                if item.kind.isVisual {
                    ThumbnailImage(url: url, size: CGSize(width: 420, height: 420))
                } else {
                    DocumentFace(item: item, url: url)
                }
            }
            .overlay(alignment: .bottom) { if item.kind.isVisual { Caption(item: item) } }
            .overlay(alignment: .topTrailing) {
                if item.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.black.opacity(0.35), in: .circle)
                        .padding(10)
                }
            }
            .background(Color.white.opacity(0.05))
            .clipShape(shape)
            .overlay { shape.strokeBorder(.white.opacity(0.09), lineWidth: 0.75) }
            .overlay { if let progress { ProgressVeil(progress: progress) } }
            .overlay(alignment: .bottomTrailing) {
                if showsMenu, !(menu is EmptyView) {
                    CardMenuButton { menu }
                }
            }
            .contentShape(shape)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(item.name), \(item.caption)"))
    }
}

/// The "…" in a card's corner. Platform menus can't be drawn through a shader, so when a card has effects on it,
/// put this over the card *after* the effects rather than inside it.
public struct CardMenuButton<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(4)
    }
}

public extension DropCard where Menu == EmptyView {
    init(item: DropItem, url: URL, progress: Double? = nil) {
        self.init(item: item, url: url, progress: progress, showsMenu: false) { EmptyView() }
    }
}

enum CardShape {
    /// Pictures keep their shape, within reason; documents are pages.
    static func ratio(for kind: DropItem.Kind, aspectRatio: Double?) -> CGFloat {
        guard kind.isVisual else { return 0.8 }
        return CGFloat(min(1.5, max(0.66, aspectRatio ?? 1)))
    }
}

/// The name and size over the bottom of a picture.
private struct Caption: View {
    let item: DropItem

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.name)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(item.caption)
                .font(.system(size: 10.5))
                .opacity(0.75)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .padding(.trailing, 34)
        .padding(.top, 26)
        .padding(.bottom, 10)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
    }
}

/// A document: its first page, small and lifted, its type in glowing letters, its name.
private struct DocumentFace: View {
    let item: DropItem
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(item.badge)
                    .font(.brand(13, weight: .heavy))
                    .glowingForeground()
                Spacer()
            }
            Spacer(minLength: 8)
            ZStack {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .ultraLight))
                    .glowingForeground()
                ThumbnailImage(url: url, size: CGSize(width: 260, height: 340))
                    .clipShape(.rect(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
            }
            .frame(maxWidth: .infinity)
            .rotationEffect(.degrees(-2))
            Spacer(minLength: 8)
            Text(item.name)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white)
            Text(item.caption)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.trailing, 26)
        }
        .padding(12)
        .background(
            LinearGradient(colors: [Color.white.opacity(0.09), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
    }

    private var symbol: String {
        switch item.kind {
        case .pdf: "doc.richtext"
        case .text: "doc.plaintext"
        case .audio: "waveform"
        case .archive: "doc.zipper"
        default: "doc"
        }
    }
}

/// A card-shaped pool of light for a file on its way in, with a ring that fills.
public struct IncomingCard: View {
    public var transfer: Transfer

    public init(transfer: Transfer) {
        self.transfer = transfer
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DropCard<EmptyView>.cornerRadius, style: .continuous)
        Color.clear
            .aspectRatio(CardShape.ratio(for: transfer.kind, aspectRatio: transfer.aspectRatio), contentMode: .fit)
            .overlay { AuroraBackground(intensity: 1).ignoresSafeArea(edges: []) }
            .overlay { ProgressVeil(progress: transfer.fraction) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(transfer.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(transfer.completed.fileSize) of \(transfer.byteCount.fileSize)")
                        .font(.system(size: 10.5).monospacedDigit())
                        .opacity(0.7)
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.white)
                .padding(12)
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Glow.text, lineWidth: 1).opacity(0.5) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Receiving \(transfer.name), \(Int(transfer.fraction * 100)) percent"))
    }
}

/// A ring of light filling round a glass disc.
private struct ProgressVeil: View {
    var progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 46, height: 46)
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 3)
                .frame(width: 34, height: 34)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(Glow.ring, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 34, height: 34)
                .animation(.smooth(duration: 0.25), value: progress)
        }
        .environment(\.colorScheme, .dark)
        .transition(.opacity)
    }
}
