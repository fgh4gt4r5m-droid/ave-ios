import Foundation

public enum TransportMessage: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

/// Une instance = une connexion. Le client en crée une nouvelle à chaque (re)connexion.
public protocol WebSocketTransport: Sendable {
    /// Ouvre la socket ; lève si l'ouverture échoue.
    func open() async throws
    func send(_ message: TransportMessage) async throws
    /// Flux des messages reçus. Se termine proprement à la fermeture, lève sur erreur réseau.
    var incoming: AsyncThrowingStream<TransportMessage, Error> { get }
    func close()
}

public typealias TransportFactory = @Sendable (URL) -> any WebSocketTransport
