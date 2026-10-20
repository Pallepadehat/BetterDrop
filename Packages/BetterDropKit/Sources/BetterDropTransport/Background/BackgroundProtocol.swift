import BetterDropCore
import Foundation

/// The HTTP the phone's background transfers speak to the Mac's ``FileServer``. Plain HTTP on the local network,
/// carrying files sealed with ``FileCipher``: iOS only keeps moving files after you leave the app if it's a
/// URLSession doing it, and URLSession speaks HTTP.
///
///     PUT /v1/files                        phone → Mac, an encrypted file as the body
///         X-BetterDrop-Device: <phone ID>
///         X-BetterDrop-Salt:   <base64url>             makes the file key, with the pairing secret
///         X-BetterDrop-Offer:  <base64url>             the FileOffer, sealed with the file key
///     → 201 Created | 401 Unauthorized | 400 Bad Request
///
///     GET /v1/files/<token>                phone ← Mac, a file the Mac offered with .backgroundOffer
///         X-BetterDrop-Device: <phone ID>
///     → 200 OK, the encrypted file | 404 Not Found
///
/// Being able to seal the offer with a key derived from the pairing secret is what proves the phone is paired.
public enum BackgroundProtocol {
    /// Files at least this big go the background way; smaller ones are quicker over the live connection.
    public static let threshold: Int64 = 8 * 1024 * 1024

    static let uploadPath = "/v1/files"
    static let downloadPrefix = "/v1/files/"
    static let deviceHeader = "x-betterdrop-device"
    static let saltHeader = "x-betterdrop-salt"
    static let offerHeader = "x-betterdrop-offer"

    public static func shouldUseBackground(for byteCount: Int64) -> Bool { byteCount >= threshold }

    /// The base URL for a file server, picking an address the phone can reach.
    public static func baseURL(for address: FileServerAddress, preferring host: String?) -> URL? {
        // The live connection's address is the one we know works, if it's IPv4; iOS's background downloader can't
        // follow IPv6 link-local addresses, so otherwise use what the Mac told us.
        let candidates = [host].compactMap { $0 }.filter { $0.contains(".") && !$0.contains(":") } + address.hosts
        guard let chosen = candidates.first else { return nil }
        return URL(string: "http://\(chosen):\(address.port)")
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        self.init(base64Encoded: base64)
    }
}
