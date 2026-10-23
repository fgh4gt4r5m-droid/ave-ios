import AVECore

/// Textes affichés à l'utilisateur. Honnêtes : aucune promesse de latence, aucune langue annoncée
/// comme disponible si le serveur n'a pas de moteur.
public enum UserMessages {
    public static func turnError(code: String, retryAfterSeconds: Int? = nil) -> String {
        switch code {
        case "language_unavailable":
            return "Cette langue n'a pas encore de moteur vocal. Choisissez le français pour parler avec l'assistant."
        case "unsupported_language":
            return "Cette langue n'est pas prise en charge."
        case "language_not_allowed":
            return "Cette langue n'est pas autorisée pour votre accès."
        case "routing_failed":
            return "Je n'ai pas pu déterminer la langue. Choisissez-la dans la liste."
        case "asr_failed":
            return "Je n'ai pas pu comprendre l'audio. Vous pouvez réessayer."
        case "rate_limited":
            guard let seconds = retryAfterSeconds, seconds >= 1 else { return "Vous envoyez trop de messages. Patientez un instant." }
            return "Vous envoyez trop de messages. Réessayez dans \(seconds) s."
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
        case .languageNotAllowed: return "Cette langue n'est pas autorisée pour votre accès."
        case .badOutput, .badVad, .codecMismatch: return "Réglage incompatible avec le serveur. Mettez l'application à jour."
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
    public static let textInputUnavailable = "La saisie de texte n'est pas disponible avec ce serveur."
    public static func learningRevoked(deleted: Int?) -> String {
        guard let deleted, deleted > 0 else { return "Votre aide a été retirée." }
        return "Votre aide a été retirée. \(deleted) élément\(deleted > 1 ? "s" : "") effacé\(deleted > 1 ? "s" : "")."
    }
    public static let learningThanks = "Merci pour votre aide."
    public static let feedbackThanks = "Merci pour votre avis."
    public static let feedbackTooLong = "Votre correction est trop longue (1 000 caractères au maximum)."
    public static let notConnected = "Pas de connexion : message non envoyé. Réessayez dans un instant."
    public static let textTooLong = "Message trop long (4 000 caractères au maximum)."
    /// État réel du moteur au 2026-10-23 (dialogue en écho, voix de test). Affiché seulement si l'app l'active.
    /// Historique gardé sur l'iPhone : le moteur, lui, ne se souvient pas d'une session à l'autre.
    public static let resumedWithoutMemory = "Conversation reprise : l'assistant ne se souvient pas de ce qui précède."
    public static let waitingForNetwork = "En attente du réseau"
    public static let offlineQueued = "Hors connexion. Vos messages partiront au retour du réseau."
    public static let demoEngine ="Version d'essai : l'assistant répète ce que vous dites et sa voix est un son de test."
}
