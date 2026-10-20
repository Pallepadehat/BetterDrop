// swift-tools-version: 6.2
import PackageDescription

// Everything the Mac and iPhone apps share. The apps themselves are thin: they put these pieces on screen.
//
//   BetterDropCore       models, the library on disk, the wire format and the crypto. No UI, no networking.
//   BetterDropTransport  finding devices (Bonjour + Bluetooth proximity) and moving files between them.
//   BetterDropUI         the look: the glow, the bloom, the cards and the grid, the same on both platforms.
let package = Package(
    name: "BetterDropKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "BetterDropCore", targets: ["BetterDropCore"]),
        .library(name: "BetterDropTransport", targets: ["BetterDropTransport"]),
        .library(name: "BetterDropUI", targets: ["BetterDropUI"]),
    ],
    targets: [
        .target(name: "BetterDropCore"),
        .target(name: "BetterDropTransport", dependencies: ["BetterDropCore"]),
        .target(name: "BetterDropUI", dependencies: ["BetterDropCore"]),
        .testTarget(name: "BetterDropCoreTests", dependencies: ["BetterDropCore"]),
        .testTarget(name: "BetterDropTransportTests", dependencies: ["BetterDropTransport"]),
    ]
)
