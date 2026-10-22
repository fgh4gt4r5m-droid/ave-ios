import AVECore
import Foundation

/// Configuration d'AVE pour une app (l'app AVE elle-même ou une app hôte qui intègre AVEKit).
public struct AVEConfiguration: Sendable {
    public var endpoint: AVEEndpoint
    public var defaultLanguage: AVELanguage
    public var tokenProvider: AVETokenProvider
    public var logger: AVELogger

    public init(endpoint: AVEEndpoint, defaultLanguage: AVELanguage = .auto,
                tokenProvider: @escaping AVETokenProvider = { nil },
                logger: AVELogger = .silent) {
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
        let client = AVEWebSocketClient.Configuration(endpoint: endpoint, lang: language ?? defaultLanguage)
        return AVEWebSocketClient(configuration: client, tokenProvider: tokenProvider,
                                  transportFactory: transportFactory, logger: logger)
    }
}
