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
    /// Historique gardé sur l'iPhone : le moteur, lui, ne se souvient pas d'une session à l'autre.
    public static let resumedWithoutMemory = "Conversation reprise : l'assistant ne se souvient pas de ce qui précède."
    public static let waitingForNetwork = "En attente du réseau"
    public static let offlineQueued = "Hors connexion. Vos messages partiront au retour du réseau."
    /// État réel du moteur au 2026-10-23 (dialogue en écho, voix de test). Affiché seulement si l'app l'active.
    public static let demoEngine = "Version d'essai : l'assistant répète ce que vous dites et sa voix est un son de test."
    /// Build de démo sans moteur en ligne : les réponses viennent de l'iPhone (`DemoEngineTransport`).
    public static let demoOffline = "Démo hors ligne : aucun moteur connecté. Les réponses viennent de l'iPhone, avec un son de test."

    // MARK: Fichiers et images (maquette validée le 2026-10-23, tableau « Le message pour chaque erreur »)

    /// Message pour un code d'erreur des fichiers ou des tâches (HTTP ou `task_error`). La règle de modération n'est
    /// jamais détaillée (`content_refused`).
    public static func mediaError(code: String, retryAfterSeconds: Int? = nil) -> String {
        switch code {
        case "file_too_large": return "Ce fichier est trop lourd : 10 Mo au maximum."
        case "unsupported_type":
            return "Ce type de fichier n'est pas pris en charge. Envoyez une photo, un PDF, un document Word ou un texte."
        case "no_text": return "Ce PDF ne contient pas de texte lisible (c'est peut-être un scan). Envoyez plutôt une photo de la page."
        case "language_unavailable": return "Pour l'instant, je ne traduis qu'entre le français et l'anglais."
        case "content_refused": return "Je ne peux pas créer cette image. Essayez une autre demande."
        case "rights_not_confirmed": return "Cochez la case d'accord pour retoucher cette photo."
        case "moderation_unavailable":
            return "Je ne peux pas vérifier cette image pour l'instant, donc je ne la crée pas. Réessayez dans un moment."
        case "quota_exceeded":
            guard let seconds = retryAfterSeconds, seconds >= 1 else { return "Vous avez atteint la limite pour aujourd'hui." }
            return "Vous avez atteint la limite pour aujourd'hui. Réessayez dans \(duration(seconds))."
        case "rate_limited":
            guard let seconds = retryAfterSeconds, seconds >= 1 else { return "Trop de demandes d'un coup. Patientez un instant." }
            return "Trop de demandes d'un coup. Réessayez dans \(duration(seconds))."
        case "feature_disabled": return "Cette fonction n'est pas encore disponible."
        case "cancelled": return "Création annulée."
        case "low_quality":
            return "Le résultat n'était pas réussi, je ne vous l'ai pas montré. Réessayez, peut-être avec une autre description."
        case "file_not_found": return "Le fichier a expiré (il est gardé 1 h). Joignez-le de nouveau."
        case "bad_request": return "La demande n'a pas pu être traitée. Réessayez."
        case "unauthorized": return "Connexion refusée. Reconnectez-vous ou vérifiez votre accès."
        // Codes de l'app (pas du moteur).
        case "network": return "Pas de connexion : demande non envoyée. Réessayez dans un instant."
        case "download_failed": return "Le résultat n'a pas pu être téléchargé. Réessayez."
        case "image_unreadable": return "Cette image n'a pas pu être lue. Essayez avec une autre photo."
        case "file_missing": return "Ce fichier n'est plus sur l'iPhone. Joignez-le de nouveau."
        case "prompt_too_long": return "Description trop longue (1 000 caractères au maximum)."
        default:
            // `engine_unavailable`, `storage_full`, `extraction_unavailable`, `failed` et tout code inconnu.
            return "Le service est momentanément indisponible. Réessayez dans un moment."
        }
    }

    /// « 45 s », « 2 min », « 3 h » (arrondi au-dessus : on ne fait pas attendre moins qu'annoncé).
    public static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(max(seconds, 1)) s" }
        if seconds < 3600 { return "\((seconds + 59) / 60) min" }
        return "\((seconds + 3599) / 3600) h"
    }

    /// Mention obligatoire tant que le moteur est factice (`simulated: true`).
    public static let simulatedImage = "Le moteur d'images n'est pas encore branché : ceci n'est pas une vraie image."
    public static let simulatedDocument = "Document de démonstration : le texte est renvoyé tel quel, sans traitement réel."
    public static let generatedByAI = "Générée par IA"
    public static let simulatedBadge = "Image de démonstration"
    public static let mediaUnavailable = "Les fichiers et les images ne sont pas disponibles dans cette version."
    public static let imageCreationHint =
        "Créée par une IA. Les personnages imaginaires, même photoréalistes, sont possibles ; une personne réelle nommée, non."
    /// Case d'accord des CGU (`CGU-CONTENUS-IA.md` §2) : retoucher la photo d'une personne réelle exige son accord.
    public static let rightsConfirmation = "Je confirme être sur cette photo, ou avoir l'accord des personnes présentes."
    public static let fileForgotten = "La photo est oubliée par le serveur au bout d'1 h."
    public static let cropIsLocal =
        "Recadrer se fait sur l'iPhone, tout de suite, sans rien envoyer. Prolonger (l'IA invente les bords), agrandir et modifier passent par le moteur."

    // Signalement (E17). Ne JAMAIS dire « envoyé » si le moteur ne l'a pas gardé.
    public static let reportHidden = "L'image est masquée tout de suite sur cet iPhone."
    public static let reportSent = "Merci. Une personne va examiner ce signalement. L'image reste masquée sur cet iPhone."
    public static let reportDisabled =
        "Le signalement n'a pas pu être enregistré pour l'instant. L'image reste masquée sur cet iPhone."
    public static let reportFailed =
        "Le signalement n'a pas été envoyé (pas de connexion ?). L'image reste masquée sur cet iPhone."

    public static func reportReason(_ reason: ReportReason) -> String {
        switch reason {
        case .minors: return "Mineur concerné"
        case .sexual: return "Contenu sexuel"
        case .violent: return "Violence"
        case .hate: return "Haine ou discrimination"
        case .realPerson: return "Personne réelle reconnaissable"
        case .misleading: return "Contenu trompeur"
        case .other: return "Autre raison"
        }
    }
}
