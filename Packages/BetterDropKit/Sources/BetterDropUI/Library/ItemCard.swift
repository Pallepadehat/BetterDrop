import BetterDropCore
import SwiftUI

/// One file in the grid: its picture (or its first page), its name, and how big and how old it is.
///
/// Pictures and videos keep their shape; documents are drawn as a page with a badge, like a sheet of paper on the
/// table.
public struct ItemCard<Menu: View>: View {
    public var item: DropItem
    public var url: URL
    /// Set while the file is being sent: 0 to 1.
    public var progress: Double?
    private let menu: Menu

    public init(item: DropItem, url: URL, progress: Double? = nil, @ViewBuilder menu: () -> Menu) {
        self.item = item
        self.url = url
        self.progress = progress
        self.menu = menu()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardArtwork(kind: item.kind, badge: item.badge, aspectRatio: item.aspectRatio, url: url)
                .overlay { if let progress { ProgressVeil(progress: progress) } }
            CardFooter(name: item.name, caption: item.caption, menu: menu)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(item.name), \(item.caption)"))
    }
}

public extension ItemCard where Menu == EmptyView {
    init(item: DropItem, url: URL, progress: Double? = nil) {
        self.init(item: item, url: url, progress: progress) { EmptyView() }
    }
}

/// A card for a file still on its way in: the shape it'll have, filling with light as it arrives.
public struct IncomingCard: View {
    public var transfer: Transfer

    public init(transfer: Transfer) {
        self.transfer = transfer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: CardArtwork.cornerRadius, style: .continuous)
                .fill(.quaternary)
                .aspectRatio(CardArtwork.shape(for: transfer.kind, aspectRatio: transfer.aspectRatio), contentMode: .fit)
                .overlay { ProgressVeil(progress: transfer.fraction) }
            CardFooter(name: transfer.name,
                       caption: String(localized: "From \(transfer.peerName) · \(transfer.completed.fileSize) of \(transfer.byteCount.fileSize)"),
                       menu: EmptyView())
        }
        .accessibilityElement(children: .combine)
    }
}

struct CardArtwork: View {
    var kind: DropItem.Kind
    var badge: String
    var aspectRatio: Double?
    var url: URL

    static let cornerRadius: CGFloat = 14

    /// Wide panoramas and tall screenshots are reined in a little so the grid stays tidy.
    static func shape(for kind: DropItem.Kind, aspectRatio: Double?) -> CGFloat {
        guard kind.isVisual else { return 0.78 }
        return CGFloat(min(1.6, max(0.62, aspectRatio ?? 1)))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        Color.clear
            .aspectRatio(Self.shape(for: kind, aspectRatio: aspectRatio), contentMode: .fit)
            .overlay {
                if kind.isVisual {
                    ThumbnailImage(url: url, size: CGSize(width: 400, height: 400))
                } else {
                    DocumentPage(kind: kind, badge: badge, url: url)
                }
            }
            .background(.quaternary.opacity(kind.isVisual ? 1 : 0))
            .clipShape(shape)
            .overlay {
                if kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.ultraThinMaterial, in: .circle)
                        .environment(\.colorScheme, .dark)
                }
            }
            .overlay { shape.strokeBorder(.white.opacity(0.08)) }
    }
}

/// A document, drawn as a page with its first page on it (when Quick Look can make one) and a type badge.
private struct DocumentPage: View {
    var kind: DropItem.Kind
    var badge: String
    var url: URL

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white)
                .overlay {
                    ZStack {
                        Image(systemName: symbol)
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.black.opacity(0.18))
                        ThumbnailImage(url: url, size: CGSize(width: 300, height: 400))
                    }
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                }
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .padding(EdgeInsets(top: 10, leading: 14, bottom: 22, trailing: 14))
            Text(badge)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.55), in: .capsule)
                .padding(8)
        }
        .background(.fill.tertiary)
    }

    private var symbol: String {
        switch kind {
        case .pdf: "doc.richtext"
        case .text: "doc.text"
        case .audio: "waveform"
        case .archive: "doc.zipper"
        default: "doc"
        }
    }
}

private struct CardFooter<Menu: View>: View {
    var name: String
    var caption: String
    var menu: Menu

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !(menu is EmptyView) {
                SwiftUI.Menu {
                    menu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 22)
                        .contentShape(.rect)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 2)
    }
}

/// A dimmed card with a ring that fills as the bytes move.
private struct ProgressVeil: View {
    var progress: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CardArtwork.cornerRadius, style: .continuous)
                .fill(.black.opacity(0.35))
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 4)
                .frame(width: 40, height: 40)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: Glow.colors + [Glow.colors[0]], center: .center),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 40, height: 40)
                .animation(.linear(duration: 0.2), value: progress)
        }
        .transition(.opacity)
    }
}
