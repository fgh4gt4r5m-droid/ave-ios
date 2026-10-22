import Foundation

/// Messages texte client → serveur (docs/PROTOCOL.md). L'audio micro est binaire : voir `AudioFrame`.
public enum ClientMessage: Sendable, Equatable {
    case hello(Hello)
    case endOfSpeech(meta: [String: JSONValue]?)
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

        public init(lang: AVELanguage, sampleRate: Int = 16_000, sessionID: String? = nil,
                    lastSeq: UInt32? = nil, token: String? = nil) {
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
        case lastSeq = "last_seq", token, meta, t
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
        case .endOfSpeech(let meta):
            try c.encode("end_of_speech", forKey: .type)
            try c.encodeIfPresent(meta, forKey: .meta)
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

public enum AVEProtocolError: Error, Equatable, Sendable {
    case frameTooShort
    case unexpectedKind(UInt8)
    case invalidUTF8
    case malformedEvent(type: String)
}
