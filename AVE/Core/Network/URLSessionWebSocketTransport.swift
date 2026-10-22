import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Transport réel basé sur `URLSessionWebSocketTask`.
public final class URLSessionWebSocketTransport: WebSocketTransport, @unchecked Sendable {
    // @unchecked : `task` n'est utilisée que via ses méthodes thread-safe (send/receive/cancel)
    // et les champs sont immuables après init.
    private let session: URLSession
    private let task: URLSessionWebSocketTask
    public let incoming: AsyncThrowingStream<TransportMessage, Error>
    private let continuation: AsyncThrowingStream<TransportMessage, Error>.Continuation

    public init(url: URL, session: URLSession = .shared) {
        self.session = session
        self.task = session.webSocketTask(with: url)
        self.task.maximumMessageSize = 1 << 20
        let (stream, continuation) = AsyncThrowingStream<TransportMessage, Error>.makeStream()
        self.incoming = stream
        self.continuation = continuation
    }

    public static let factory: TransportFactory = { url in URLSessionWebSocketTransport(url: url) }

    public func open() async throws {
        task.resume()
        // La boucle de réception démarre tout de suite ; une erreur de handshake y remonte.
        let task = self.task
        let continuation = self.continuation
        Task.detached {
            do {
                while true {
                    switch try await task.receive() {
                    case .string(let s): continuation.yield(.text(s))
                    case .data(let d): continuation.yield(.binary(d))
                    @unknown default: break
                    }
                }
            } catch {
                // Fermeture normale ou erreur : dans les deux cas la connexion est finie.
                if task.closeCode == .normalClosure {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: error)
                }
            }
        }
        continuation.onTermination = { [task] _ in
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    public func send(_ message: TransportMessage) async throws {
        switch message {
        case .text(let s): try await task.send(.string(s))
        case .binary(let d): try await task.send(.data(d))
        }
    }

    public func close() {
        task.cancel(with: .normalClosure, reason: nil)
        continuation.finish()
    }
}
