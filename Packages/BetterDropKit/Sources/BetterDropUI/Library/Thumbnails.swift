import CoreGraphics
import Foundation
import QuickLookThumbnailing
import SwiftUI

/// Makes and remembers thumbnails with Quick Look, which knows pictures, videos, PDFs, documents and more, on both
/// platforms.
public actor ThumbnailCache {
    public static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, CGImageBox>()

    private final class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    public init() {
        cache.countLimit = 300
    }

    public func thumbnail(for url: URL, size: CGSize, scale: CGFloat) async -> CGImage? {
        let key = "\(url.path(percentEncoded: false))|\(Int(size.width))x\(Int(size.height))@\(scale)" as NSString
        if let hit = cache.object(forKey: key) { return hit.image }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let image = representation.cgImage
        cache.setObject(CGImageBox(image), forKey: key)
        return image
    }

    public func forget(_ url: URL) {
        // NSCache can't list its keys; this is rare (a file was replaced), so start over.
        cache.removeAllObjects()
    }
}

/// A file's thumbnail, faded in when it's ready.
struct ThumbnailImage: View {
    let url: URL
    let size: CGSize
    @State private var image: CGImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: scale)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .task(id: url) {
            let loaded = await ThumbnailCache.shared.thumbnail(for: url, size: size, scale: scale)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}
