import Foundation

/// Événement serveur → client décodé. Un type inconnu donne `.unknown` : le protocole
/// évolue, le client doit l'ignorer (et le journaliser) sans planter la session.
public enum ServerEvent: Sendable, Equatable {
    case ready(Ready)
    case replayed(count: Int, gap: Bool)
    case pong(t: Double?)
    case error(code: String, message: String)
    /// Exactement UN transcript par tour vocal, toujours FINAL. `source == .text` : écho d'un message `text`.
    /// `speculative` veut dire « calculé d'avance » (vad:server), jamais « provisoire » : on l'affiche comme les autres.
    case transcript(text: String, lang: String, confidence: Double, speculative: Bool, source: TranscriptSource)
    /// Action métier à exécuter par l'application. `confirm == true` : accord explicite de l'utilisateur requis.
    case action(name: String, args: [String: JSONValue], confirm: Bool)
    case ttsStart(utteranceID: Int, sampleRate: Int, latencyMs: Int)
    case ttsEnd(utteranceID: Int, interrupted: Bool)
    /// Clôt TOUJOURS un tour (les clients texte seul n'ont pas de `tts_end`).
    case turnEnd(utteranceID: Int, interrupted: Bool)
    case interrupted
    /// Une phrase de la réponse, émise avant son audio.
    case replyText(utteranceID: Int, text: String, lang: String)
    /// Échec d'un tour, session ouverte. `turn_end` suit, sauf pour `rate_limited`.
    /// `retryAfterSeconds` : seulement pour `rate_limited` (entier ≥ 1).
    case turnError(code: String, message: String, lang: String?, retryAfterSeconds: Int?)
    /// Détection de parole côté serveur (seulement avec `vad:"server"`) : ignorés par l'app (`vad:"client"`).
    case speechStart, speechEnd
    case languageSet(lang: String)
    case unknown(type: String)

    public enum TranscriptSource: String, Sendable, Equatable { case voice, text }

    public struct Ready: Sendable, Equatable {
        public let sessionID: String
        public let resumed: Bool
        public let lastMicSeq: UInt32
        public let seq: UInt32
        public let protocolVersion: Int
        /// Durée de grâce de la session après une coupure (30 s).
        public let graceSeconds: Double?
        /// Langues du registre avec leur disponibilité réelle. `nil` sur un serveur ancien.
        public let languages: [LanguageInfo]?
    }
}

/// Un événement avec son `seq` (présent sur tous les événements sauf ready/replayed/pong/error).
public struct ServerFrame: Sendable, Equatable {
    public let seq: UInt32?
    public let event: ServerEvent

    public init(seq: UInt32?, event: ServerEvent) {
        self.seq = seq
        self.event = event
    }

    private struct Envelope: Decodable { let type: String; let seq: UInt32? }

    /// Décode une trame texte. Lève `malformedEvent` si un type connu a des champs invalides ;
    /// ne lève jamais pour un type inconnu.
    public static func decode(_ text: String) throws -> ServerFrame {
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        let env = try decoder.decode(Envelope.self, from: data)
        func body<T: Decodable>(_ type: T.Type) throws -> T {
            do { return try decoder.decode(T.self, from: data) } catch {
                throw AVEProtocolError.malformedEvent(type: env.type)
            }
        }
        let event: ServerEvent
        switch env.type {
        case "ready":
            struct B: Decodable {
                let session_id: String; let resumed: Bool; let last_mic_seq: UInt32
                let seq: UInt32; let protocolVersion: Int
                let graceSeconds: Double?; let languages: [LanguageInfo]?
                enum CodingKeys: String, CodingKey {
                    case session_id, resumed, last_mic_seq, seq, protocolVersion = "protocol"
                    case graceSeconds = "grace_s", languages
                }

                // Les champs ajoutés au fil des versions (grace_s est un FLOTTANT : 30.0, languages) ne
                // doivent JAMAIS empêcher la lecture de `ready` : sans lui, la session n'est jamais prête.
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    session_id = try c.decode(String.self, forKey: .session_id)
                    resumed = try c.decode(Bool.self, forKey: .resumed)
                    last_mic_seq = try c.decode(UInt32.self, forKey: .last_mic_seq)
                    seq = try c.decode(UInt32.self, forKey: .seq)
                    protocolVersion = try c.decode(Int.self, forKey: .protocolVersion)
                    graceSeconds = try? c.decodeIfPresent(Double.self, forKey: .graceSeconds)
                    languages = try? c.decodeIfPresent([LanguageInfo].self, forKey: .languages)
                }
            }
            let b = try body(B.self)
            event = .ready(.init(sessionID: b.session_id, resumed: b.resumed, lastMicSeq: b.last_mic_seq,
                                 seq: b.seq, protocolVersion: b.protocolVersion,
                                 graceSeconds: b.graceSeconds, languages: b.languages))
        case "replayed":
            struct B: Decodable { let count: Int; let gap: Bool }
            let b = try body(B.self)
            event = .replayed(count: b.count, gap: b.gap)
        case "pong":
            struct B: Decodable { let t: Double? }
            event = .pong(t: try body(B.self).t)
        case "error":
            struct B: Decodable { let code: String; let message: String? }
            let b = try body(B.self)
            event = .error(code: b.code, message: b.message ?? "")
        case "transcript":
            struct B: Decodable {
                let text: String; let lang: String; let confidence: Double?
                let speculative: Bool?; let source: String?
            }
            let b = try body(B.self)
            event = .transcript(text: b.text, lang: b.lang, confidence: b.confidence ?? 1,
                                speculative: b.speculative ?? false,
                                source: b.source == "text" ? .text : .voice)
        case "action":
            struct B: Decodable { let name: String; let args: [String: JSONValue]?; let confirm: Bool? }
            let b = try body(B.self)
            // Un `confirm` absent est traité comme `true` : mieux vaut demander que d'exécuter à tort.
            event = .action(name: b.name, args: b.args ?? [:], confirm: b.confirm ?? true)
        case "tts_start":
            struct B: Decodable { let utterance_id: Int; let sample_rate: Int; let latency_ms: Int }
            let b = try body(B.self)
            event = .ttsStart(utteranceID: b.utterance_id, sampleRate: b.sample_rate, latencyMs: b.latency_ms)
        case "tts_end":
            struct B: Decodable { let utterance_id: Int; let interrupted: Bool }
            let b = try body(B.self)
            event = .ttsEnd(utteranceID: b.utterance_id, interrupted: b.interrupted)
        case "turn_end":
            struct B: Decodable { let utterance_id: Int; let interrupted: Bool }
            let b = try body(B.self)
            event = .turnEnd(utteranceID: b.utterance_id, interrupted: b.interrupted)
        case "interrupted":
            event = .interrupted
        case "reply_text":
            struct B: Decodable { let utterance_id: Int; let text: String; let lang: String? }
            let b = try body(B.self)
            event = .replyText(utteranceID: b.utterance_id, text: b.text, lang: b.lang ?? "")
        case "turn_error":
            struct B: Decodable {
                let code: String; let message: String?; let lang: String?
                let retry_after_s: Int?
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    code = try c.decode(String.self, forKey: .code)
                    message = try? c.decodeIfPresent(String.self, forKey: .message)
                    lang = try? c.decodeIfPresent(String.self, forKey: .lang)
                    retry_after_s = try? c.decodeIfPresent(Int.self, forKey: .retry_after_s)
                }
                enum CodingKeys: String, CodingKey { case code, message, lang, retry_after_s }
            }
            let b = try body(B.self)
            event = .turnError(code: b.code, message: b.message ?? "", lang: b.lang, retryAfterSeconds: b.retry_after_s)
        case "speech_start":
            event = .speechStart
        case "speech_end":
            event = .speechEnd
        case "language_set":
            struct B: Decodable { let lang: String }
            event = .languageSet(lang: try body(B.self).lang)
        default:
            event = .unknown(type: env.type)
        }
        // Le `seq` de ready/replayed/pong/error n'appartient pas à la numérotation de reprise.
        switch event {
        case .ready, .replayed, .pong, .error:
            return ServerFrame(seq: nil, event: event)
        default:
            return ServerFrame(seq: env.seq, event: event)
        }
    }
}
