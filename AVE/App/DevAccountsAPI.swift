import AVECore
import Foundation

/// FAUX service de comptes : développement (DEBUG sans adresse) et build TestFlight « démo interface »
/// (`AVE_DEMO_ACCOUNTS = YES`, workflow `ave-testflight-demo`, export réservé aux testeurs internes, donc jamais publiable).
/// Accepte n'importe quel numéro ; le code est toujours « 000000 » ; aucun SMS n'est envoyé. Le jeton « dev-token » n'a de
/// sens que contre un serveur AVE lancé avec `AVE_AUTH=none` : il n'ouvre rien ailleurs. Compilé dans tous les builds pour
/// pouvoir être choisi par un réglage plutôt que par une condition de compilation (le build démo est un build Release).
struct DevAccountsAPI: AccountsAPI {
    func requestOTP(phone: PhoneNumber, channel: OTPChannel) async throws -> OTPChallenge {
        OTPChallenge(id: "dev", retryAfterSeconds: 30)
    }

    func verifyOTP(challengeID: String, code: String) async throws -> AuthCredentials {
        guard code == "000000" else { throw AuthError.wrongCode }
        return AuthCredentials(refreshToken: "dev-refresh", kind: .phone)
    }

    func signInWithApple(identityToken: String, rawNonce: String, authorizationCode: String?) async throws -> AuthCredentials {
        AuthCredentials(refreshToken: "dev-refresh", kind: .apple)
    }

    func guestChallenge() async throws -> Data { Data([1]) }

    func signInAsGuest(_ attestation: GuestAttestation, challenge: Data) async throws -> AuthCredentials {
        AuthCredentials(refreshToken: "dev-refresh", kind: .guest)
    }

    func accessToken(refreshToken: String) async throws -> AccessToken {
        AccessToken(token: "dev-token", expiresAt: Date().addingTimeInterval(600))
    }

    func signOut(refreshToken: String) async throws {}
    func deleteAccount(refreshToken: String) async throws { DevProfileStore.shared.set(AccountProfile()) }

    // Profil gardé en mémoire le temps du lancement : l'entrée (nom, âge, conditions) se parcourt comme en vrai.
    func profile(refreshToken: String) async throws -> AccountProfile { DevProfileStore.shared.get() }

    func updateProfile(refreshToken: String, fullName: String?, termsVersion: String?, adultConfirmed: Bool?)
        async throws -> AccountProfile {
        var profile = DevProfileStore.shared.get()
        if let fullName { profile.fullName = fullName }
        if let termsVersion { profile.termsVersion = termsVersion }
        if adultConfirmed == true { profile.adultConfirmed = true }
        DevProfileStore.shared.set(profile)
        return profile
    }
}

private final class DevProfileStore: @unchecked Sendable {
    static let shared = DevProfileStore()
    private let lock = NSLock()
    private var profile = AccountProfile()
    func get() -> AccountProfile { lock.withLock { profile } }
    func set(_ new: AccountProfile) { lock.withLock { profile = new } }
}
