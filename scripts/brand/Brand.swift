import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Draws BetterDrop's icons and the README's pictures with the app's own Metal shaders
// (Packages/BetterDropKit/Sources/BetterDropUI/Shaders/Light.metal), so the brand is the product.
// Run it through scripts/make-brand.sh.

@main
struct Brand {
    @MainActor static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else {
            print("usage: brand <Light.metallib> <AppIcon.appiconset> <docs/images>")
            exit(1)
        }
        let art = Art(shaders: ShaderLibrary(url: URL(fileURLWithPath: arguments[1])))
        let iconSet = URL(fileURLWithPath: arguments[2])
        let images = URL(fileURLWithPath: arguments[3])
        try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)

        // iOS gets one full-bleed square (it rounds the corners itself); the Mac a rounded tile with a margin, at
        // every size.
        try write(art.render(art.iosIcon, size: 1024), to: iconSet.appending(path: "icon-ios-1024.png"))
        var entries = [#"    { "filename" : "icon-ios-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }"#]
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = "icon-mac-\(points)@\(scale)x.png"
                try write(art.render(art.macIcon, size: CGFloat(points * scale)), to: iconSet.appending(path: name))
                entries.append(#"    { "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(points)x\#(points)" }"#)
            }
        }
        let contents = "{\n  \"images\" : [\n\(entries.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
        try contents.write(to: iconSet.appending(path: "Contents.json"), atomically: true, encoding: .utf8)

        try write(art.render(art.macIcon, size: 512), to: images.appending(path: "icon.png"))
        try write(art.render(art.socialPreview, width: 1280, height: 640), to: images.appending(path: "social-preview.png"))
        try write(art.render(art.banner, width: 1600, height: 640), to: images.appending(path: "banner.png"))
        try writeGIF(frames: 60, to: images.appending(path: "orb.gif")) { art.render(art.orbFrame(time: $0), width: 300, height: 300) }
        try writeGIF(frames: 60, to: images.appending(path: "reach.gif")) { art.render(art.reachFrame(time: $0), width: 300, height: 300) }
        try writeGIF(frames: 60, to: images.appending(path: "portal.gif")) { art.render(art.portalFrame(time: $0), width: 300, height: 300) }
        try writeGIF(frames: 54, to: images.appending(path: "dissolve.gif")) { art.render(art.dissolveFrame(time: $0), width: 300, height: 300) }
        print("Brand written to \(iconSet.path) and \(images.path)")
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    /// An endlessly looping GIF at 30 frames a second, `time` going 0 to 1 over the loop.
    @MainActor
    static func writeGIF(frames: Int, to url: URL, frame: (Double) -> CGImage) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil) else { return }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let delay = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 30]] as CFDictionary
        for index in 0..<frames {
            CGImageDestinationAddImage(destination, frame(Double(index) / Double(frames)), delay)
        }
        CGImageDestinationFinalize(destination)
    }
}

@MainActor
struct Art {
    let shaders: ShaderLibrary
    static let ink = Color(red: 0.03, green: 0.03, blue: 0.05)
    static let glow = LinearGradient(colors: [
        Color(red: 1.00, green: 0.62, blue: 0.38), Color(red: 1.00, green: 0.36, blue: 0.52),
        Color(red: 0.84, green: 0.36, blue: 0.95), Color(red: 0.52, green: 0.42, blue: 1.00),
    ], startPoint: .leading, endPoint: .trailing)

    func render(_ view: some View, size: CGFloat) -> CGImage {
        render(view, width: size, height: size)
    }

    func render(_ view: some View, width: CGFloat, height: CGFloat) -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height))
        renderer.scale = 1
        return renderer.cgImage!
    }

    func orb(energy: Float, lean: Float = 0, charge: Float = 0, time: Float = 8.4) -> some View {
        Rectangle().colorEffect(shaders.Orb(.boundingRect, .float(time), .float(energy), .float2(lean, 0), .float(charge)))
    }

    func aurora(_ intensity: Float, time: Float = 6) -> some View {
        Rectangle().colorEffect(shaders.Aurora(.boundingRect, .float(time), .float(intensity)))
    }

    // MARK: Icons

    /// The orb, bright, on a deep violet night.
    var iosIcon: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack {
                Self.ink
                RadialGradient(colors: [Color(red: 0.22, green: 0.1, blue: 0.34), Self.ink], center: .center,
                               startRadius: 0, endRadius: side * 0.72)
                    .frame(width: side, height: side)
                orb(energy: 0.85).frame(width: side * 1.3, height: side * 1.3).position(x: side / 2, y: side / 2)
            }
        }
    }

    var macIcon: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            let tile = side * 0.8
            iosIcon
                .frame(width: tile, height: tile)
                .clipShape(RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: max(0.5, side / 512))
                }
                .shadow(color: .black.opacity(0.35), radius: side * 0.02, y: side * 0.012)
                .frame(width: side, height: side)
        }
    }

    // MARK: Pictures

    var socialPreview: some View {
        ZStack {
            Self.ink
            aurora(0.9)
            HStack(spacing: 30) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("BetterDrop")
                        .font(.system(size: 108, weight: .bold, design: .rounded))
                        .tracking(-2)
                        .foregroundStyle(.white)
                    Text("AirDrop, reimagined as light.")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundStyle(Self.glow)
                    Text("Fling files between your iPhone and your Mac.\nEnd-to-end encrypted. Open source.")
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineSpacing(4)
                }
                .padding(.leading, 80)
                Spacer(minLength: 0)
                orb(energy: 0.85, lean: -0.35).frame(width: 520, height: 520).padding(.trailing, 20)
            }
        }
    }

    var banner: some View {
        ZStack {
            Self.ink
            aurora(0.75, time: 11)
            Rectangle().colorEffect(shaders.Portal(.boundingRect, .float(5), .float(0.5), .float(1), .float(0.7), .float(0)))
                .frame(width: 560)
                .frame(maxWidth: .infinity, alignment: .trailing)
            orb(energy: 0.9, lean: 0.55, time: 3.1).frame(width: 560, height: 560).offset(x: 260)
            VStack(alignment: .leading, spacing: 14) {
                Text("BetterDrop")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .tracking(-2)
                    .foregroundStyle(.white)
                Text("AirDrop, reimagined as light.")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(Self.glow)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 90)
        }
    }

    // MARK: Animations

    func orbFrame(time: Double) -> some View {
        ZStack {
            Self.ink
            orb(energy: Float(0.5 + 0.3 * sin(time * 2 * .pi)), time: Float(20 + time * 4))
        }
    }

    /// The orb reaching for the edge as the phone nears the Mac, and letting go.
    func reachFrame(time: Double) -> some View {
        let reach = Float(pow(sin(time * .pi), 2))
        return ZStack {
            Self.ink
            aurora(reach * 0.8, time: Float(10 + time * 3))
            orb(energy: 0.3 + 0.7 * reach, lean: -0.9 * reach, time: Float(4 + time * 4)).frame(width: 280, height: 280)
            Rectangle().colorEffect(shaders.EdgeGlow(.boundingRect, .float(Float(time * 4)), .float(0.15 + 0.8 * reach),
                                                     .float(-1), .float(36), .float(0)))
        }
    }

    /// The Mac's edge, waking as a phone comes close.
    func portalFrame(time: Double) -> some View {
        let near = Float(0.5 + 0.5 * sin(time * 2 * .pi - .pi / 2))
        return ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.2, blue: 0.3), Color(red: 0.05, green: 0.06, blue: 0.1)],
                           startPoint: .top, endPoint: .bottom)
            Rectangle().colorEffect(shaders.Portal(.boundingRect, .float(Float(30 + time * 3)), .float(0.15 + 0.6 * near),
                                                   .float(1), .float(near), .float(0)))
        }
    }

    /// A photo burning into light and condensing back.
    func dissolveFrame(time: Double) -> some View {
        let progress = time < 0.5 ? time * 2 : 2 - time * 2
        return ZStack {
            Self.ink
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.6, blue: 0.35), Color(red: 0.55, green: 0.3, blue: 0.75),
                                              Color(red: 0.15, green: 0.18, blue: 0.4)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Golden Hour.jpg").font(.system(size: 15, weight: .semibold))
                        Text("367 KB · 13:25").font(.system(size: 12)).opacity(0.75)
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                }
                .frame(width: 180, height: 220)
                .layerEffect(shaders.Dissolve(.boundingRect, .float(Float(progress)), .float2(-1, -0.2)), maxSampleOffset: .zero)
                .offset(x: -CGFloat(progress) * 50)
        }
    }
}
