import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads what the library needs to know about a file without decoding it: its type and, for pictures and videos,
/// its shape.
enum MediaInspector {
    static func contentType(of url: URL) -> UTType {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType { return type }
        return UTType(filenameExtension: url.pathExtension) ?? .data
    }

    static func aspectRatio(of url: URL, type: UTType) async -> Double? {
        if type.conforms(to: .image) { return imageAspectRatio(of: url) }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return await videoAspectRatio(of: url) }
        return nil
    }

    private static func imageAspectRatio(of url: URL) -> Double? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0
        else { return nil }
        // Orientations 5–8 are rotated a quarter turn, so the picture is as tall as the pixels are wide.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? height / width : width / height
    }

    private static func videoAspectRatio(of url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform)
        else { return nil }
        let shown = size.applying(transform)
        let width = abs(shown.width), height = abs(shown.height)
        return width > 0 && height > 0 ? width / height : nil
    }
}
