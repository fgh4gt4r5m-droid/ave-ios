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
    func deleteAccount(refreshToken: String) async throws {}
}
