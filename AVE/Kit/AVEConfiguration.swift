import AVECore
import Foundation

/// Configuration d'AVE pour une app (l'app AVE elle-même ou une app hôte qui intègre AVEKit).
public struct AVEConfiguration: Sendable {
    public var endpoint: AVEEndpoint
    public var defaultLanguage: AVELanguage
    public var tokenProvider: AVETokenProvider
    public var logger: AVELogger
    /// Identification de l'app hôte (WoYo, TaGa…) pour la console ; aucune donnée personnelle.
    public var clientInfo: ClientInfo?

    public init(endpoint: AVEEndpoint, defaultLanguage: AVELanguage = .auto,
                tokenProvider: @escaping AVETokenProvider = { nil },
                logger: AVELogger = .silent, clientInfo: ClientInfo? = nil) {
        self.clientInfo = clientInfo
        self.endpoint = endpoint
        self.defaultLanguage = defaultLanguage
        self.tokenProvider = tokenProvider
        self.logger = logger
    }

    /// Un client = une session. L'app crée un client par conversation vocale/texte.
    public func makeClient(
        language: AVELanguage? = nil,
        transportFactory: @escaping TransportFactory = URLSessionWebSocketTransport.factory
    ) -> AVEWebSocketClient {
        let client = AVEWebSocketClient.Configuration(endpoint: endpoint, lang: language ?? defaultLanguage,
                                                  clientInfo: clientInfo)
        return AVEWebSocketClient(configuration: client, tokenProvider: tokenProvider,
                                  transportFactory: transportFactory, logger: logger)
    }
}
