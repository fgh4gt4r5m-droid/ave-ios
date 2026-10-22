import Foundation

public enum AccountKind: String, Sendable, Codable, Equatable {
    case phone, apple, guest
}

/// Justificatif long (jeton de rafraîchissement) du service de comptes. Il ne sert qu'à obtenir des jetons AVE courts.
public struct AuthCredentials: Sendable, Equatable {
    public let refreshToken: String
    public let kind: AccountKind

    public init(refreshToken: String, kind: AccountKind) {
        self.refreshToken = refreshToken
        self.kind = kind
    }
}

/// Jeton court de `POST /v1/token`, mis dans `hello.token`.
public struct AccessToken: Sendable, Equatable {
    public let token: String
    public let expiresAt: Date

    public init(token: String, expiresAt: Date) {
        self.token = token
        self.expiresAt = expiresAt
    }
}

public struct OTPChallenge: Sendable, Equatable {
    public let id: String
    public let retryAfterSeconds: Int?

    public init(id: String, retryAfterSeconds: Int? = nil) {
        self.id = id
        self.retryAfterSeconds = retryAfterSeconds
    }
}

public enum OTPChannel: String, Sendable, Equatable {
    case sms, whatsapp
}

public struct GuestAttestation: Sendable, Equatable {
    public let keyID: String
    public let attestation: Data

    public init(keyID: String, attestation: Data) {
        self.keyID = keyID
        self.attestation = attestation
    }
}

public enum AuthError: Error, Equatable, Sendable {
    case invalidPhone
    case invalidCode
    case wrongCode
    case tooManyAttempts(retryAfterSeconds: Int?)
    /// Identifiants refusés (jeton Apple invalide, attestation refusée…).
    case rejected
    /// Le jeton de rafraîchissement n'est plus valable : il faut se reconnecter.
    case signedOut
    case guestUnsupported
    case network
    case unavailable
}

/// Attestation d'appareil pour le mode invité (limite les abus). Implémentation iOS : App Attest.
public protocol GuestAttesting: Sendable {
    func attest(challenge: Data) async throws -> GuestAttestation
}
