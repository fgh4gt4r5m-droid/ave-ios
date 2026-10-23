import AVECore
import Foundation

/// Un fichier montré dans la conversation : une photo ou un document joint par la personne, ou un résultat produit par le
/// moteur. Le fichier lui-même est gardé sur l'iPhone (`MediaStore`, `localName`) ; le moteur, lui, l'oublie au bout d'1 h.
public struct MediaItem: Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case image, document }
    /// `attachment` : joint par la personne (une retouche exige la case d'accord) ; `generated` : produit par AVE.
    public enum Origin: String, Codable, Sendable { case attachment, generated }
    public enum State: Sendable, Equatable {
        case ready
        /// L'envoi au moteur a échoué : le fichier reste visible avec le message d'erreur (`UserMessages.mediaError`).
        case failed(code: String)
    }

    public var kind: Kind
    public var origin: Origin
    /// Nom montré (`IMG_2214.jpg`, `contrat-bail (anglais).txt`).
    public var title: String
    /// Chemin dans le `MediaStore` ; `nil` si le fichier n'a pas pu être gardé.
    public var localName: String?
    public var mime: String
    public var byteCount: Int
    public var width: Int?
    public var height: Int?
    /// Fichier connu du moteur, valable jusqu'à `expiresAt` (secondes Unix). Absent : à renvoyer avant une tâche.
    public var fileID: String?
    public var expiresAt: Int?
    /// Résultat du moteur factice : ce n'est pas une vraie image (ou le document est renvoyé tel quel). Toujours affiché.
    public var simulated: Bool
    /// Tâche qui a produit ce fichier (pour le signalement).
    public var taskID: String?
    /// Masqué sur cet iPhone après un signalement.
    public var hidden: Bool
    /// La personne a coché la case d'accord pour cette photo (une seule fois par photo).
    public var rightsConfirmed: Bool
    public var state: State
    /// Demande qui a produit ce fichier (« Refaire »). Pas gardée dans l'historique.
    public var request: MediaTaskRequest?

    public init(kind: Kind, origin: Origin, title: String, localName: String?, mime: String, byteCount: Int,
                width: Int? = nil, height: Int? = nil, fileID: String? = nil, expiresAt: Int? = nil,
                simulated: Bool = false, taskID: String? = nil, hidden: Bool = false, rightsConfirmed: Bool = false,
                state: State = .ready, request: MediaTaskRequest? = nil) {
        self.kind = kind
        self.origin = origin
        self.title = title
        self.localName = localName
        self.mime = mime
        self.byteCount = byteCount
        self.width = width
        self.height = height
        self.fileID = fileID
        self.expiresAt = expiresAt
        self.simulated = simulated
        self.taskID = taskID
        self.hidden = hidden
        self.rightsConfirmed = rightsConfirmed
        self.state = state
        self.request = request
    }

    /// `file_id` encore utilisable : le moteur oublie le fichier au bout d'1 h ; marge de 2 min pour le trajet de la demande.
    public func hasValidFileID(now: Date = Date()) -> Bool {
        guard fileID != nil, let expiresAt else { return false }
        return Double(expiresAt) - now.timeIntervalSince1970 > 120
    }

    /// Une retouche par le moteur exige l'accord de la personne pour une photo qu'elle a jointe, jamais pour une image d'AVE.
    public var needsRightsConfirmation: Bool { origin == .attachment && kind == .image }

    /// La case d'accord est demandée quand le moteur verra une photo ENVOYÉE : une photo jointe, ou une image d'AVE dont
    /// le moteur a oublié le fichier (elle repartira de l'iPhone et il ne saura plus qu'elle vient de lui).
    public func requiresRightsForTask(now: Date = Date()) -> Bool {
        kind == .image && (origin == .attachment || !hasValidFileID(now: now))
    }
}

/// Une tâche demandée au moteur (créer, retoucher, agrandir, prolonger, transformer un document), affichée comme une carte
/// tant qu'elle n'a pas abouti. `ref` relie la carte aux événements `task_*`.
public struct MediaTaskCard: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        /// Demande envoyée, `task_started` pas encore reçu.
        case sending
        /// Le moteur travaille ; `estimatedSeconds` est SON estimation (non mesurée), jamais une promesse de l'app.
        case working(startedAt: Date, estimatedSeconds: Int?)
        /// `task_done` reçu, téléchargement du résultat en cours.
        case downloading
        case failed(code: String, retryAfterSeconds: Int?)
        case cancelled
    }

    /// Renouvelé à chaque nouvel essai : les événements d'un essai abandonné ne touchent plus la carte.
    public var ref: String
    public var request: MediaTaskRequest
    /// Message dont le fichier est la source (photo, document) ; `nil` pour une image créée d'après une description.
    public let sourceMessageID: Int?
    /// Nom donné au fichier produit (document : « contrat-bail (anglais).txt »).
    public let resultTitle: String
    public var taskID: String?
    public var state: State
    /// Résultat reçu mais pas encore téléchargé (pour réessayer le téléchargement sans refaire la tâche).
    public var pendingResult: MediaTaskResult?
    /// La session qui attendait la tâche est perdue : ses événements n'arriveront plus, l'app interroge
    /// `GET /v1/tasks/{task_id}` jusqu'au résultat (D1).
    public var detached = false

    public init(ref: String, request: MediaTaskRequest, sourceMessageID: Int? = nil, resultTitle: String,
                taskID: String? = nil, state: State = .sending, pendingResult: MediaTaskResult? = nil) {
        self.ref = ref
        self.request = request
        self.sourceMessageID = sourceMessageID
        self.resultTitle = resultTitle
        self.taskID = taskID
        self.state = state
        self.pendingResult = pendingResult
    }

    public var kind: MediaTaskKind { request.kind }

    /// Annulation possible tant que le moteur n'a pas rendu son résultat.
    public var canCancel: Bool {
        switch state {
        case .sending, .working: return true
        default: return false
        }
    }

    public var isFinished: Bool {
        switch state {
        case .failed, .cancelled: return true
        default: return false
        }
    }
}

extension MediaTaskRequest {
    /// La même demande avec un autre `ref` et, si donné, un autre `file_id` (fichier renvoyé après expiration).
    public func replacing(fileID newFileID: String? = nil, ref newRef: String) -> MediaTaskRequest {
        switch self {
        case .imageGenerate(let prompt, let size, let quality, _):
            return .imageGenerate(prompt: prompt, size: size, quality: quality, ref: newRef)
        case .imageEdit(let fileID, let instruction, let quality, let rights, _):
            return .imageEdit(fileID: newFileID ?? fileID, instruction: instruction, quality: quality, rightsConfirmed: rights,
                              ref: newRef)
        case .imageUpscale(let fileID, let target, let rights, _):
            return .imageUpscale(fileID: newFileID ?? fileID, target: target, rightsConfirmed: rights, ref: newRef)
        case .imageExtend(let fileID, let aspect, let quality, let rights, _):
            return .imageExtend(fileID: newFileID ?? fileID, aspect: aspect, quality: quality, rightsConfirmed: rights, ref: newRef)
        case .documentTransform(let fileID, let action, let lang, let instruction, _):
            return .documentTransform(fileID: newFileID ?? fileID, action: action, targetLang: lang, instruction: instruction,
                                      ref: newRef)
        }
    }
}

/// Pièce jointe en cours d'envoi, montrée dans la barre de saisie (aperçu, taille, croix pour l'enlever).
public struct AttachmentDraft: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let kind: MediaItem.Kind
    public let byteCount: Int
    public let localName: String?
}

/// Libellés et noms de fichiers des tâches, purs et testés.
public enum MediaTaskText {
    /// Ce que la carte affiche pendant le travail.
    public static func workingTitle(for request: MediaTaskRequest) -> String {
        switch request {
        case .imageGenerate: return "Création de l'image…"
        case .imageEdit: return "Retouche de la photo…"
        case .imageUpscale(_, let target, _, _): return target == .uhd ? "Agrandissement en 4K…" : "Agrandissement en 1080p…"
        case .imageExtend: return "Prolongement de l'image…"
        case .documentTransform(_, let action, _, _, _):
            switch action {
            case .translate: return "Traduction du document…"
            case .summarize: return "Résumé du document…"
            case .rewrite: return "Reformulation du document…"
            }
        }
    }

    /// La demande telle que la personne la voit dans sa bulle (raccourci touché).
    public static func userLabel(action: DocumentAction, targetLang: String?, instruction: String?) -> String {
        switch action {
        case .translate: return targetLang == "fra" ? "Traduire en français" : "Traduire en anglais"
        case .summarize: return "Résumer"
        case .rewrite:
            let text = (instruction ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "Reformuler" : "Reformuler : \(text)"
        }
    }

    /// `contrat-bail.pdf` + traduction en anglais → `contrat-bail (anglais).txt` (le moteur rend du texte UTF-8).
    public static func documentResultTitle(source: String, action: DocumentAction, targetLang: String?) -> String {
        let stem = (source as NSString).deletingPathExtension
        let base = stem.isEmpty ? "document" : stem
        let suffix: String
        switch action {
        case .translate: suffix = targetLang == "fra" ? "français" : "anglais"
        case .summarize: suffix = "résumé"
        case .rewrite: suffix = "reformulé"
        }
        return "\(base) (\(suffix)).txt"
    }

    /// Nom d'une image produite, daté pour s'y retrouver dans Photos ou Fichiers.
    public static func imageResultTitle(mime: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "AVE \(formatter.string(from: date)).\(fileExtension(forMime: mime))"
    }

    public static func fileExtension(forMime mime: String) -> String {
        switch mime.lowercased() {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "application/pdf": return "pdf"
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document": return "docx"
        default: return mime.lowercased().hasPrefix("text/") ? "txt" : "bin"
        }
    }

    /// « Environ 35 s », « Environ 2 min » : l'estimation du MOTEUR, présentée comme telle.
    public static func estimate(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        return "Environ \(UserMessages.duration(seconds))"
    }
}
