import Foundation

public enum AVEEndpointError: Error, Equatable, Sendable {
    case invalidURL
    case insecureSchemeNotAllowed
    case credentialsInURL
}

/// Valide l'URL du serveur : `wss` uniquement. `ws` n'est toléré qu'en développement
/// (`allowInsecureLocalNetwork`) et seulement vers localhost / réseau privé / `.local`.
/// Aucun jeton ne doit figurer dans l'URL (il part dans le `hello`).
public struct AVEEndpoint: Sendable, Equatable {
    public let url: URL

    public init(_ url: URL, allowInsecureLocalNetwork: Bool = false) throws {
        guard let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
            throw AVEEndpointError.invalidURL
        }
        guard url.user == nil, url.password == nil, url.query == nil else {
            throw AVEEndpointError.credentialsInURL
        }
        switch scheme {
        case "wss": break
        case "ws":
            guard allowInsecureLocalNetwork, Self.isLocalNetworkHost(host) else {
                throw AVEEndpointError.insecureSchemeNotAllowed
            }
        default:
            throw AVEEndpointError.invalidURL
        }
        self.url = url
    }

    static func isLocalNetworkHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h.hasSuffix(".local") { return true }
        let parts = h.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4, h.split(separator: ".").count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (127, _), (10, _), (192, 168): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}
