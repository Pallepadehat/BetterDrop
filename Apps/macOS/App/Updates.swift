import AppKit
import Sparkle

/// Keeps BetterDrop up to date with Sparkle. Once a day it reads the appcast attached to the latest GitHub release
/// (one small download; nothing about you is sent). A new version is downloaded, checked against the EdDSA key in
/// Info.plist, swapped in and relaunched.
///
/// Releases aren't signed with an Apple Developer ID yet, only ad hoc, so the EdDSA signature is what proves an
/// update really came from us.
final class Updates {
    static let shared = Updates()

    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    func start() {
        // Builds from Xcode stay as they are, rather than being swapped for the latest release.
        #if !DEBUG
        controller.startUpdater()
        #endif
    }

    func checkNow() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
