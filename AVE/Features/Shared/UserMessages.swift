import AVECore

/// Textes affichés à l'utilisateur. Honnêtes : aucune promesse de latence, aucune langue annoncée
/// comme disponible si le serveur n'a pas de moteur.
public enum UserMessages {
    public static func turnError(code: String) -> String {
        switch code {
        case "language_unavailable":
            return "Cette langue n'a pas encore de moteur vocal. Choisissez le français pour parler avec l'assistant."
        default:
            return "Un problème est survenu pendant cette réponse. Vous pouvez réessayer."
        }
    }

    public static func fatal(_ error: AVEFatalError) -> String {
        switch error {
        case .unauthorized: return "Connexion refusée. Reconnectez-vous ou vérifiez votre accès."
        case .tooManySessions: return "Trop de sessions sont ouvertes. Fermez-en une puis réessayez."
        case .badVersion: return "Cette version de l'application n'est plus compatible avec le serveur. Mettez-la à jour."
        case .unsupportedCodec, .badSampleRate: return "Le serveur n'accepte pas le format audio de cet appareil."
        case .badLang: return "Le serveur ne reconnaît pas cette langue."
        }
    }

    public static func connection(_ state: ConnectionState) -> String? {
        switch state {
        case .idle, .open: return nil
        case .connecting: return "Connexion…"
        case .reconnecting: return "Connexion perdue. Reconnexion…"
        case .closed: return "Session terminée."
        case .failed(let e): return fatal(e)
        }
    }

    public static let sessionRestarted = "La session précédente a expiré : la conversation repart de zéro."
    public static let responseTruncated = "Une partie de la réponse a été perdue pendant la coupure réseau."
    public static let noResponse = "L'assistant n'a pas répondu. Vous pouvez réessayer."
    public static let microphoneDenied = "Accès au micro refusé : le mode vocal est désactivé. Vous pouvez l'autoriser dans les Réglages."
    public static let audioUnavailable = "Impossible d'activer l'audio sur cet appareil."
    public static let textInputUnavailable = "La saisie de texte n'est pas encore disponible : le serveur ne sait recevoir que la voix."
}
