import AVECore

/// Textes de la connexion, en français : courts, sans jargon (beaucoup d'utilisateurs ne lisent pas couramment).
public enum AuthMessages {
    public static func message(for error: AuthError) -> String {
        switch error {
        case .invalidPhone: return "Ce numéro n'est pas valide. Vérifiez-le, avec l'indicatif du pays."
        case .invalidCode: return "Entrez le code reçu : des chiffres uniquement."
        case .wrongCode: return "Ce code est incorrect."
        case .tooManyAttempts(let seconds):
            guard let seconds, seconds >= 1 else { return "Trop d'essais. Réessayez dans un instant." }
            return "Trop d'essais. Réessayez dans \(seconds) s."
        case .rejected: return "Connexion refusée. Réessayez ou choisissez une autre méthode."
        case .signedOut: return "Votre session a expiré. Reconnectez-vous."
        case .guestUnsupported: return "Le mode invité n'est pas disponible sur cet appareil."
        case .network: return "Pas de connexion. Vérifiez votre réseau."
        case .unavailable: return "Le service est momentanément indisponible. Réessayez."
        }
    }
}
