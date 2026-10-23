import Foundation

/// Service de comptes, SÉPARÉ du moteur AVE (qui n'authentifie que des jetons). Spécification proposée dans
/// `contrat/CONTRAT.md` §6 : AUCUN serveur n'existe encore, ces appels ne sont validés que contre des faux.
public protocol AccountsAPI: Sendable {
    func requestOTP(phone: PhoneNumber, channel: OTPChannel) async throws -> OTPChallenge
    func verifyOTP(challengeID: String, code: String) async throws -> AuthCredentials
    /// `authorizationCode` : code d'autorisation d'Apple, échangé par le service pour pouvoir RÉVOQUER le jeton Apple à la
    /// suppression du compte (App Store, règle 5.1.1(v)). Facultatif : Apple peut ne pas le fournir.
    func signInWithApple(identityToken: String, rawNonce: String, authorizationCode: String?) async throws -> AuthCredentials
    func guestChallenge() async throws -> Data
    func signInAsGuest(_ attestation: GuestAttestation, challenge: Data) async throws -> AuthCredentials
    /// Échange le jeton long contre un jeton AVE court (le service appelle `POST /v1/token` avec la clé B2B, que l'app ne voit jamais).
    func accessToken(refreshToken: String) async throws -> AccessToken
    func signOut(refreshToken: String) async throws
    func deleteAccount(refreshToken: String) async throws
    /// Profil du compte (nom complet, conditions, âge).
    func profile(refreshToken: String) async throws -> AccountProfile
    /// Champs `nil` : inchangés. `adultConfirmed` ne s'envoie qu'à `true`.
    func updateProfile(refreshToken: String, fullName: String?, termsVersion: String?, adultConfirmed: Bool?)
        async throws -> AccountProfile
}

extension AccountsAPI {
    /// Service sans profil (app hôte, faux service de test) : l'app ne peut rien relire ni enregistrer.
    public func profile(refreshToken: String) async throws -> AccountProfile { throw AuthError.unavailable }

    public func updateProfile(refreshToken: String, fullName: String?, termsVersion: String?, adultConfirmed: Bool?)
        async throws -> AccountProfile { throw AuthError.unavailable }
}
