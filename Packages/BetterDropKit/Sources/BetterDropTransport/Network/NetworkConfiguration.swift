import Network

/// How BetterDrop talks on the network.
public enum NetworkConfiguration {
    /// The Bonjour service the Mac advertises and the phone looks for. Also listed under `NSBonjourServices`.
    public static let serviceType = "_betterdrop._tcp"

    /// TCP with keepalives, so a phone that walks away is noticed in seconds rather than minutes, over Wi-Fi or
    /// directly between devices (AWDL, the same peer-to-peer link AirDrop uses).
    public static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        tcp.connectionTimeout = 10
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}
