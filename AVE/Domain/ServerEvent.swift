import Foundation

/// Événement serveur → client décodé. Un type inconnu donne `.unknown` : le protocole
/// évolue, le client doit l'ignorer (et le journaliser) sans planter la session.
public enum ServerEvent: Sendable, Equatable {
    case ready(Ready)
    case replayed(count: Int, gap: Bool)
    case pong(t: Double?)
    case error(code: String, message: String)
    case transcript(text: String, lang: String, confidence: Double)
    case toolCall(name: String, args: [String: JSONValue])
    case ttsStart(utteranceID: Int, sampleRate: Int, latencyMs: Int)
    case ttsEnd(utteranceID: Int, interrupted: Bool)
    case interrupted
    /// NON VÉRIFIÉ : absent de docs/PROTOCOL.md et du serveur du sprint 1. Forme supposée `{text}`.
    case replyText(text: String)
    /// NON VÉRIFIÉ : absent du serveur du sprint 1. Forme supposée `{code, message?}`.
    case turnError(code: String, message: String?)
    case unknown(type: String)

    public struct Ready: Sendable, Equatable {
        public let sessionID: String
        public let resumed: Bool
        public let lastMicSeq: UInt32
        public let seq: UInt32
        public let protocolVersion: Int
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
                enum CodingKeys: String, CodingKey {
                    case session_id, resumed, last_mic_seq, seq, protocolVersion = "protocol"
                }
            }
            let b = try body(B.self)
            event = .ready(.init(sessionID: b.session_id, resumed: b.resumed, lastMicSeq: b.last_mic_seq,
                                 seq: b.seq, protocolVersion: b.protocolVersion))
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
            struct B: Decodable { let text: String; let lang: String; let confidence: Double? }
            let b = try body(B.self)
            event = .transcript(text: b.text, lang: b.lang, confidence: b.confidence ?? 1)
        case "tool_call":
            struct B: Decodable { let name: String; let args: [String: JSONValue]? }
            let b = try body(B.self)
            event = .toolCall(name: b.name, args: b.args ?? [:])
        case "tts_start":
            struct B: Decodable { let utterance_id: Int; let sample_rate: Int; let latency_ms: Int }
            let b = try body(B.self)
            event = .ttsStart(utteranceID: b.utterance_id, sampleRate: b.sample_rate, latencyMs: b.latency_ms)
        case "tts_end":
            struct B: Decodable { let utterance_id: Int; let interrupted: Bool }
            let b = try body(B.self)
            event = .ttsEnd(utteranceID: b.utterance_id, interrupted: b.interrupted)
        case "interrupted":
            event = .interrupted
        case "reply_text":
            struct B: Decodable { let text: String }
            event = .replyText(text: try body(B.self).text)
        case "turn_error":
            struct B: Decodable { let code: String; let message: String? }
            let b = try body(B.self)
            event = .turnError(code: b.code, message: b.message)
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
