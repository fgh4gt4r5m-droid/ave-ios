import Foundation

/// Messages texte client → serveur (docs/PROTOCOL.md). L'audio micro est binaire : voir `AudioFrame`.
public enum ClientMessage: Sendable, Equatable {
    case hello(Hello)
    case endOfSpeech(meta: [String: JSONValue]?)
    /// Entrée texte (1–4000 caractères). Le serveur répond par un écho `transcript {source:"text"}`.
    case text(String)
    /// Synthèse à la demande (≤ 1000 caractères), sans passer par le LLM.
    case speak(text: String, lang: AVELanguage?)
    case setLanguage(AVELanguage)
    /// Réponse à la demande d'aide à l'amélioration. `version` = `notice_version` de la notice RÉELLEMENT affichée.
    case learningConsent(granted: Bool, version: String)
    /// Retire le consentement ET efface côté serveur ce qui a été gardé pour ce sujet.
    case learningRevoke
    case feedback(utteranceID: Int?, rating: FeedbackRating, correction: String?)
    case interrupt
    case ping(t: Double)
    case bye
    /// Tâche sur un fichier ou une image (E16) ; la réponse arrive par les événements `task_*`, reliés par `ref`.
    case task(MediaTaskRequest)
    /// Pas de réponse directe : la tâche émet `task_error {code:"cancelled"}`.
    case taskCancel(taskID: String)
    /// Contexte d'une conversation rouverte (D9) : une fois, juste après un `ready` neuf, avant toute entrée.
    case context([ContextMessage])

    public struct Hello: Sendable, Equatable {
        public var version: Int = 1
        public var codec: String = "pcm16"
        public var lang: AVELanguage
        public var sampleRate: Int
        public var sessionID: String?
        public var lastSeq: UInt32?
        /// Jeton d'authentification, lu du Keychain. ASSOMPTION : le nom de champ `token` n'est
        /// pas défini dans docs/PROTOCOL.md (l'authentification y est « hors périmètre »).
        public var token: String?
        /// Qui détecte la fin de parole. Défaut serveur = `server`. L'app envoie `client` : elle ne
        /// transmet le micro que pendant la parole (économie de débit en 3G) et signale `end_of_speech`.
        public var vad: VADMode?
        public var client: ClientInfo?
        /// `nil` : le défaut du serveur (`audio`, `text`, `actions`). Avec `text_delta` (D7) : fragments `reply_delta`.
        public var output: [String]?

        public init(lang: AVELanguage, sampleRate: Int = 16_000, sessionID: String? = nil,
                    lastSeq: UInt32? = nil, token: String? = nil, vad: VADMode? = nil, client: ClientInfo? = nil,
                    output: [String]? = nil) {
            self.vad = vad
            self.client = client
            self.output = output
            self.lang = lang
            self.sampleRate = sampleRate
            self.sessionID = sessionID
            self.lastSeq = lastSeq
            self.token = token
        }
    }
}

extension ClientMessage: Encodable {
    private enum Keys: String, CodingKey {
        case type, version, codec, lang, sampleRate = "sample_rate", sessionID = "session_id"
        case lastSeq = "last_seq", token, meta, t, vad, client, text
        // `version` (déjà déclaré ci-dessus) sert aussi à `learning_consent` : même clé JSON.
        case granted, utteranceID = "utterance_id", rating, correction
        // Tâches (E16)
        case prompt, size, quality, ref, fileID = "file_id", instruction, rightsConfirmed = "rights_confirmed"
        case target, aspect, action, targetLang = "target_lang", taskID = "task_id"
        case output, messages
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .hello(let h):
            try c.encode("hello", forKey: .type)
            try c.encode(h.version, forKey: .version)
            try c.encode(h.codec, forKey: .codec)
            try c.encode(h.lang, forKey: .lang)
            try c.encode(h.sampleRate, forKey: .sampleRate)
            try c.encodeIfPresent(h.sessionID, forKey: .sessionID)
            try c.encodeIfPresent(h.lastSeq, forKey: .lastSeq)
            try c.encodeIfPresent(h.token, forKey: .token)
            try c.encodeIfPresent(h.vad?.rawValue, forKey: .vad)
            try c.encodeIfPresent(h.client, forKey: .client)
            try c.encodeIfPresent(h.output, forKey: .output)
        case .endOfSpeech(let meta):
            try c.encode("end_of_speech", forKey: .type)
            try c.encodeIfPresent(meta, forKey: .meta)
        case .text(let text):
            try c.encode("text", forKey: .type)
            try c.encode(text, forKey: .text)
        case .speak(let text, let lang):
            try c.encode("speak", forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encodeIfPresent(lang, forKey: .lang)
        case .setLanguage(let lang):
            try c.encode("set_language", forKey: .type)
            try c.encode(lang, forKey: .lang)
        case .learningConsent(let granted, let version):
            try c.encode("learning_consent", forKey: .type)
            try c.encode(granted, forKey: .granted)
            try c.encode(version, forKey: .version)
        case .learningRevoke:
            try c.encode("learning_revoke", forKey: .type)
        case .feedback(let utteranceID, let rating, let correction):
            try c.encode("feedback", forKey: .type)
            try c.encodeIfPresent(utteranceID, forKey: .utteranceID)
            try c.encode(rating.rawValue, forKey: .rating)
            try c.encodeIfPresent(correction, forKey: .correction)
        case .interrupt:
            try c.encode("interrupt", forKey: .type)
        case .ping(let t):
            try c.encode("ping", forKey: .type)
            try c.encode(t, forKey: .t)
        case .bye:
            try c.encode("bye", forKey: .type)
        case .task(let request):
            try c.encode(request.kind.rawValue, forKey: .type)
            try c.encode(request.ref, forKey: .ref)
            switch request {
            case .imageGenerate(let prompt, let size, let quality, _):
                try c.encode(prompt, forKey: .prompt)
                try c.encodeIfPresent(size?.rawValue, forKey: .size)
                try c.encodeIfPresent(quality?.rawValue, forKey: .quality)
            case .imageEdit(let fileID, let instruction, let quality, let rightsConfirmed, _):
                try c.encode(fileID, forKey: .fileID)
                try c.encode(instruction, forKey: .instruction)
                try c.encodeIfPresent(quality?.rawValue, forKey: .quality)
                try c.encodeIfPresent(rightsConfirmed, forKey: .rightsConfirmed)
            case .imageUpscale(let fileID, let target, let rightsConfirmed, _):
                try c.encode(fileID, forKey: .fileID)
                try c.encode(target.rawValue, forKey: .target)
                try c.encodeIfPresent(rightsConfirmed, forKey: .rightsConfirmed)
            case .imageExtend(let fileID, let aspect, let quality, let rightsConfirmed, _):
                try c.encode(fileID, forKey: .fileID)
                try c.encode(aspect.rawValue, forKey: .aspect)
                try c.encodeIfPresent(quality?.rawValue, forKey: .quality)
                try c.encodeIfPresent(rightsConfirmed, forKey: .rightsConfirmed)
            case .documentTransform(let fileID, let action, let targetLang, let instruction, _):
                try c.encode(fileID, forKey: .fileID)
                try c.encode(action.rawValue, forKey: .action)
                try c.encodeIfPresent(targetLang, forKey: .targetLang)
                try c.encodeIfPresent(instruction, forKey: .instruction)
            }
        case .taskCancel(let taskID):
            try c.encode("task_cancel", forKey: .type)
            try c.encode(taskID, forKey: .taskID)
        case .context(let messages):
            try c.encode("context", forKey: .type)
            try c.encode(messages, forKey: .messages)
        }
    }

    /// Trame texte JSON prête à envoyer.
    public func jsonString() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let s = String(data: data, encoding: .utf8) else { throw AVEProtocolError.invalidUTF8 }
        return s
    }
}

public enum FeedbackRating: String, Sendable, Equatable {
    case up, down
}

public enum VADMode: String, Sendable, Equatable {
    case server, client
}

/// Identification de l'application cliente pour la console (usage par application). Aucune donnée personnelle.
public struct ClientInfo: Sendable, Equatable, Encodable {
    public var app: String?
    public var version: String?
    public var sdk: String?

    public init(app: String? = nil, version: String? = nil, sdk: String? = nil) {
        self.app = app
        self.version = version
        self.sdk = sdk
    }
}

public enum AVEProtocolError: Error, Equatable, Sendable {
    case frameTooShort
    case unexpectedKind(UInt8)
    case invalidUTF8
    case malformedEvent(type: String)
}

/// Un message du contexte d'une conversation rouverte (D9). Bornes du moteur : `text` de 1 à 4000 caractères,
/// 20 messages et 8000 caractères en tout (au-delà, il garde les plus récents). Voir `ConversationContext`.
public struct ContextMessage: Sendable, Equatable, Encodable {
    public enum Role: String, Sendable, Equatable, Encodable { case user, assistant }
    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }

    public static let maxTextCharacters = 4000
    public static let maxMessages = 20
    public static let maxTotalCharacters = 8000
}
