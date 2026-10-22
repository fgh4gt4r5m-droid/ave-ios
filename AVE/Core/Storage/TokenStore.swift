import Foundation

/// Stockage du jeton d'authentification. Le jeton ne vit que là (et en mémoire le temps du
/// `hello`) : jamais dans l'URL, jamais dans les logs, jamais dans UserDefaults.
public protocol TokenStore: Sendable {
    func readToken() -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
}

/// Pour les tests et les previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) { self.token = token }

    public func readToken() -> String? { lock.withLock { token } }
    public func saveToken(_ token: String) throws { lock.withLock { self.token = token } }
    public func deleteToken() throws { lock.withLock { token = nil } }
}
