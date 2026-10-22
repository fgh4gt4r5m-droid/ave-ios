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
    case interrupt
    case ping(t: Double)
    case bye

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

        public init(lang: AVELanguage, sampleRate: Int = 16_000, sessionID: String? = nil,
                    lastSeq: UInt32? = nil, token: String? = nil, vad: VADMode? = nil, client: ClientInfo? = nil) {
            self.vad = vad
            self.client = client
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
        case .interrupt:
            try c.encode("interrupt", forKey: .type)
        case .ping(let t):
            try c.encode("ping", forKey: .type)
            try c.encode(t, forKey: .t)
        case .bye:
            try c.encode("bye", forKey: .type)
        }
    }

    /// Trame texte JSON prête à envoyer.
    public func jsonString() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let s = String(data: data, encoding: .utf8) else { throw AVEProtocolError.invalidUTF8 }
        return s
    }
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
