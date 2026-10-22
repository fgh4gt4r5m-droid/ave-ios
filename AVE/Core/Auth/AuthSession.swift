import Foundation

/// Session de connexion : garde le jeton long dans le Keychain, fournit un jeton AVE court à chaque
/// (re)connexion (`AVETokenProvider`), avec cache et une seule requête à la fois.
public actor AuthSession {
    public enum State: Sendable, Equatable {
        case signedOut
        case signedIn(AccountKind)
    }

    public nonisolated let states: AsyncStream<State>
    private let statesOut: AsyncStream<State>.Continuation
    private let api: any AccountsAPI
    private let store: TokenStore
    private let now: @Sendable () -> Date
    private let margin: TimeInterval
    private var credentials: AuthCredentials?
    private var cached: AccessToken?
    private var inflight: Task<AccessToken, Error>?
    private var generation = 0
    public private(set) var state: State

    public init(api: any AccountsAPI, store: TokenStore, now: @escaping @Sendable () -> Date = { Date() },
                margin: TimeInterval = 30) {
        self.api = api
        self.store = store
        self.now = now
        self.margin = margin
        let loaded = Self.decode(store.readToken())
        self.credentials = loaded
        let initial: State = loaded.map { .signedIn($0.kind) } ?? .signedOut
        self.state = initial
        let (stream, continuation) = AsyncStream<State>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.states = stream
        self.statesOut = continuation
        continuation.yield(initial)
    }

    /// Fournisseur de jeton pour `AVEConfiguration` / `AVEWebSocketClient`.
    public nonisolated func tokenProvider() -> AVETokenProvider {
        { [self] in try await self.accessToken() }
    }

    /// Enregistre la connexion réussie (jeton long dans le Keychain).
    public func adopt(_ new: AuthCredentials) throws {
        try store.saveToken(Self.encode(new))
        generation += 1
        inflight?.cancel()
        inflight = nil
        cached = nil
        credentials = new
        setState(.signedIn(new.kind))
    }

    /// Jeton court valide : du cache s'il reste plus que la marge, sinon renouvelé auprès du service de comptes.
    public func accessToken() async throws -> String {
        guard let credentials else { throw AuthError.signedOut }
        if let cached, cached.expiresAt.timeIntervalSince(now()) > margin { return cached.token }
        let task: Task<AccessToken, Error>
        if let inflight {
            task = inflight
        } else {
            let api = self.api
            task = Task { try await api.accessToken(refreshToken: credentials.refreshToken) }
            inflight = task
        }
        let gen = generation
        do {
            let token = try await task.value
            if generation == gen {
                cached = token
                inflight = nil
            }
            return token.token
        } catch AuthError.signedOut {
            if generation == gen { clear() }  // jeton long révoqué ou expiré : retour à la connexion
            throw AuthError.signedOut
        } catch {
            if generation == gen { inflight = nil }
            throw error
        }
    }

    /// Déconnexion : le serveur est prévenu au mieux, mais l'appareil est TOUJOURS déconnecté.
    public func signOut() async {
        if let credentials { try? await api.signOut(refreshToken: credentials.refreshToken) }
        clear()
    }

    /// Suppression du compte (exigée par l'App Store). En cas d'échec le compte reste connecté et l'erreur remonte.
    public func deleteAccount() async throws {
        guard let credentials else { throw AuthError.signedOut }
        try await api.deleteAccount(refreshToken: credentials.refreshToken)
        clear()
    }

    private func clear() {
        generation += 1
        inflight?.cancel()
        inflight = nil
        cached = nil
        credentials = nil
        try? store.deleteToken()
        setState(.signedOut)
    }

    private func setState(_ new: State) {
        state = new
        statesOut.yield(new)
    }

    // « type:jeton » : le type est conservé avec le jeton, dans la même entrée du Keychain.
    private static func encode(_ c: AuthCredentials) -> String { "\(c.kind.rawValue):\(c.refreshToken)" }

    private static func decode(_ raw: String?) -> AuthCredentials? {
        guard let raw, let sep = raw.firstIndex(of: ":"),
              let kind = AccountKind(rawValue: String(raw[..<sep])) else { return nil }
        let token = String(raw[raw.index(after: sep)...])
        return token.isEmpty ? nil : AuthCredentials(refreshToken: token, kind: kind)
    }
}
