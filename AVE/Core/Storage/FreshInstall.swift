import Foundation

/// iOS GARDE le trousseau (Keychain) quand on supprime une app : à la réinstallation, l'ancienne session revenait et
/// l'écran de connexion était sauté (constaté par le propriétaire sur TestFlight, 2026-10-23). Ce qu'on attend d'une app
/// supprimée, c'est qu'elle oublie tout : au premier lancement après une installation, on efface la session gardée.
///
/// Repère : une clé des préférences (UserDefaults), qui, elle, disparaît avec l'app. Absente = nouvelle installation.
public enum FreshInstall {
    public static let markerKey = "install.sessionPurged"

    /// À appeler AVANT de créer `AuthSession` (qui lit le trousseau dès sa création). Renvoie vrai si une ancienne
    /// session a été effacée. Une erreur du trousseau n'empêche pas de démarrer : le repère n'est alors pas posé, et
    /// l'effacement sera retenté au lancement suivant.
    @discardableResult
    public static func purgeStaleSession(defaults: UserDefaults = .standard, store: TokenStore) -> Bool {
        guard !defaults.bool(forKey: markerKey) else { return false }
        let hadSession = store.readToken() != nil
        do {
            try store.deleteToken()
        } catch {
            return false
        }
        defaults.set(true, forKey: markerKey)
        return hadSession
    }
}
