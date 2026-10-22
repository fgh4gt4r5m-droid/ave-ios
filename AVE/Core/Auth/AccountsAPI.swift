import Foundation

/// Service de comptes, SÉPARÉ du moteur AVE (qui n'authentifie que des jetons). Spécification proposée dans
/// `contrat/CONTRAT.md` §6 : AUCUN serveur n'existe encore, ces appels ne sont validés que contre des faux.
public protocol AccountsAPI: Sendable {
    func requestOTP(phone: PhoneNumber, channel: OTPChannel) async throws -> OTPChallenge
    func verifyOTP(challengeID: String, code: String) async throws -> AuthCredentials
    func signInWithApple(identityToken: String, rawNonce: String) async throws -> AuthCredentials
    func guestChallenge() async throws -> Data
    func signInAsGuest(_ attestation: GuestAttestation, challenge: Data) async throws -> AuthCredentials
    /// Échange le jeton long contre un jeton AVE court (le service appelle `POST /v1/token` avec la clé B2B, que l'app ne voit jamais).
    func accessToken(refreshToken: String) async throws -> AccessToken
    func signOut(refreshToken: String) async throws
    func deleteAccount(refreshToken: String) async throws
}
