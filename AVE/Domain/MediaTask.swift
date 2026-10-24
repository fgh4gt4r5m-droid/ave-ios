import Foundation

// Fichiers, documents et images (contrat E16 et E17, moteur `main` @ `db9f580`) : noms recopiés de
// `sdk/ts/src/protocol.ts`. Les tâches partent dans la WebSocket ; les fichiers passent en HTTP (`AVEFilesClient`).

public enum ImageSize: String, Sendable, Equatable, CaseIterable, Codable {
    case square, portrait, landscape
}

/// `1080p` : 1920 px sur le grand côté (défaut du moteur) ; `4k` : 3840 px.
public enum ImageQuality: String, Sendable, Equatable, CaseIterable, Codable {
    case hd = "1080p"
    case uhd = "4k"
}

public enum DocumentAction: String, Sendable, Equatable, Codable {
    case translate, summarize, rewrite
}

public enum MediaTaskKind: String, Sendable, Equatable, Codable {
    case imageGenerate = "image_generate"
    case imageEdit = "image_edit"
    case imageUpscale = "image_upscale"
    case imageExtend = "image_extend"
    case documentTransform = "document_transform"
}

/// Une demande de tâche. `ref` est choisi par l'app et renvoyé dans tous les événements `task_*` : il relie la réponse à
/// la carte affichée. `rightsConfirmed` : `true` OBLIGATOIRE pour une photo ENVOYÉE par l'utilisateur (case d'accord liée
/// aux CGU), absent pour une image produite par AVE.
public enum MediaTaskRequest: Sendable, Equatable {
    case imageGenerate(prompt: String, size: ImageSize?, quality: ImageQuality?, ref: String)
    case imageEdit(fileID: String, instruction: String, quality: ImageQuality?, rightsConfirmed: Bool?, ref: String)
    case imageUpscale(fileID: String, target: ImageQuality, rightsConfirmed: Bool?, ref: String)
    case imageExtend(fileID: String, aspect: ImageSize, quality: ImageQuality?, rightsConfirmed: Bool?, ref: String)
    /// `targetLang` : `fra` ou `eng` seulement (le moteur refuse le reste : `language_unavailable`).
    case documentTransform(fileID: String, action: DocumentAction, targetLang: String?, instruction: String?, ref: String)

    public var kind: MediaTaskKind {
        switch self {
        case .imageGenerate: return .imageGenerate
        case .imageEdit: return .imageEdit
        case .imageUpscale: return .imageUpscale
        case .imageExtend: return .imageExtend
        case .documentTransform: return .documentTransform
        }
    }

    public var ref: String {
        switch self {
        case .imageGenerate(_, _, _, let ref), .imageEdit(_, _, _, _, let ref), .imageUpscale(_, _, _, let ref),
             .imageExtend(_, _, _, _, let ref), .documentTransform(_, _, _, _, let ref):
            return ref
        }
    }

    /// Limite de la description d'une image (le moteur répond `bad_request` au-delà).
    public static let promptMaxCharacters = 1000
}

/// `task_started` : la tâche a commencé ; `estimatedSeconds` est une estimation du moteur (non mesurée).
public struct MediaTaskStarted: Sendable, Equatable {
    public let taskID: String
    public let ref: String
    public let kind: MediaTaskKind?
    public let estimatedSeconds: Int?
    /// D12 (moteur PR #38) : image lancée par le moteur depuis la conversation (`ref` « chat:<utterance_id> »).
    /// `prompt` est la description rédigée par le modèle, à montrer ; format et qualité choisis par lui.
    public let prompt: String?
    public let size: ImageSize?
    public let quality: ImageQuality?

    public init(taskID: String, ref: String, kind: MediaTaskKind?, estimatedSeconds: Int?, prompt: String? = nil,
                size: ImageSize? = nil, quality: ImageQuality? = nil) {
        self.taskID = taskID
        self.ref = ref
        self.kind = kind
        self.estimatedSeconds = estimatedSeconds
        self.prompt = prompt
        self.size = size
        self.quality = quality
    }
}

/// `task_done` : le fichier produit est à télécharger AUSSITÔT (`url`, même jeton) ; le moteur l'oublie au bout d'1 h.
public struct MediaTaskResult: Sendable, Equatable {
    public let taskID: String
    public let ref: String
    public let kind: MediaTaskKind?
    public let fileID: String
    /// `jpeg` avec le vrai moteur, `png` avec le moteur factice, `text` pour un document : lire `mime`, ne rien supposer.
    public let fileKind: String
    public let mime: String
    public let size: Int
    public let expiresAt: Int
    public let url: String
    /// Moteur factice : aucune vraie image ; l'app DOIT l'afficher.
    public let simulated: Bool
    public let width: Int?
    public let height: Int?
}

/// `task_error` : `taskID` est `nil` quand la demande est refusée avant de démarrer.
public struct MediaTaskFailure: Sendable, Equatable {
    public let taskID: String?
    public let ref: String
    public let kind: MediaTaskKind?
    public let code: String
    public let retryAfterSeconds: Int?
}

/// Réponse de `GET /v1/tasks/{task_id}` (D1 du contrat, moteur `main` @ `35a4757`) : reprise d'un résultat quand la
/// session qui attendait la tâche est perdue (coupure plus longue que le délai de grâce). `state` est une liste fermée.
public enum MediaTaskStatus: Sendable, Equatable {
    case running
    /// Mêmes champs et valeurs que `task_done`.
    case done(MediaTaskResult)
    /// Une tâche annulée répond `cancelled`. Jamais de `retry_after_s` ici.
    case failed(code: String)
}

/// Réponse de `POST /v1/files`.
public struct UploadedFile: Sendable, Equatable {
    public let fileID: String
    public let kind: String
    public let mime: String
    public let size: Int
    public let expiresAt: Int
}

/// Motifs de signalement (E17), dans l'ordre de priorité de revue du moteur.
public enum ReportReason: String, Sendable, Equatable, CaseIterable, Codable {
    case minors, sexual, violent, hate
    case realPerson = "real_person"
    case misleading, other
}

/// Limites annoncées par le moteur pour les fichiers joints.
public enum MediaLimits {
    public static let maxUploadBytes = 10 * 1024 * 1024
    public static let reportNoteMaxCharacters = 500
}
