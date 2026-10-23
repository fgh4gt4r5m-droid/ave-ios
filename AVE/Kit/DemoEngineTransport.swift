import AVECore
import Foundation

/// Moteur de DÉMONSTRATION hors ligne (décision du propriétaire, 2026-10-23) : tant que le moteur n'est pas en ligne, le
/// build de démo (`AVE_DEMO_OFFLINE=YES`) converse avec ce faux serveur, sur l'iPhone, pour qu'on puisse essayer TOUTE
/// l'interface au toucher (réflexion, réponses, historique, mode vocal, lecture, logo).
///
/// Honnêteté : il fait ce que le vrai moteur fait aujourd'hui (il répète ce qu'on lui dit, avec un son de test à la place
/// d'une voix) et ses réponses commencent par « Démo hors ligne ». L'app l'annonce aussi par un bandeau. Il ne comprend
/// pas la parole : un message vocal est signalé comme tel, jamais « transcrit ». Jamais dans le build de production.
///
/// Il parle le protocole AVE réel (mêmes trames JSON et binaires) : le client, le coordinateur et les écrans sont donc
/// exercés exactement comme avec le serveur.
public final class DemoEngineTransport: WebSocketTransport, @unchecked Sendable {
    public static let factory: TransportFactory = { _ in DemoEngineTransport() }

    public let incoming: AsyncThrowingStream<TransportMessage, Error>
    private let output: AsyncThrowingStream<TransportMessage, Error>.Continuation
    // État partagé entre `send` (appelé par le client) et les réponses différées : protégé par un verrou.
    private let lock = NSLock()
    private var seq: UInt32 = 0
    private var utterance = 0
    private var turn: Task<Void, Never>?
    /// Énoncé en cours de lecture : pour clore proprement une interruption.
    private var speaking: Int?
    private var closed = false
    /// 1 = rythme réel ; 0 = immédiat (tests).
    private let timeScale: Double

    public init(timeScale: Double = 1) {
        self.timeScale = timeScale
        let (stream, continuation) = AsyncThrowingStream<TransportMessage, Error>.makeStream()
        incoming = stream
        output = continuation
    }

    public func open() async throws {}

    public func send(_ message: TransportMessage) async throws {
        // Le micro (trames binaires) est ignoré : la démo ne reconnaît pas la parole, elle attend `end_of_speech`.
        guard case .text(let text) = message,
              let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let type = object["type"] as? String else { return }
        switch type {
        case "hello":
            // Seul le français est proposé : c'est la seule langue de la démo (et du moteur aujourd'hui).
            let french: [String: Any] = ["code": "fra", "name": "Français", "native": "Français",
                                         "regions": ["west_africa"], "status": "experimental", "available": true]
            let languages: [[String: Any]] = [french]
            emit(["type": "ready", "session_id": "demo-\(UUID().uuidString)", "resumed": false, "last_mic_seq": 0,
                  "seq": 0, "protocol": 1, "languages": languages],
                 numbered: false)
        case "text":
            let said = (object["text"] as? String) ?? ""
            startTurn(transcript: said, source: "text", reply: Self.reply(toText: said))
        case "end_of_speech":
            startTurn(transcript: Self.voiceTranscript, source: "voice", reply: Self.voiceReply)
        case "speak":
            // Lecture à voix haute : la voix seule (un son de test), close par `turn_end` comme le moteur.
            startTurn(transcript: nil, source: nil, reply: nil)
        case "interrupt":
            interrupt()
        case "ping":
            emit(["type": "pong", "t": object["t"] ?? 0], numbered: false)
        case "bye":
            close()
        default:
            break  // langue, consentement, avis : sans effet dans la démo
        }
    }

    public func close() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            closed = true
            return turn
        }
        task?.cancel()
        output.finish()
    }

    // MARK: Un tour de parole

    private func startTurn(transcript: String?, source: String?, reply: [String]?) {
        let id = lock.withLock { () -> Int in
            turn?.cancel()  // une nouvelle demande remplace la précédente, comme sur le serveur
            utterance += 1
            return utterance
        }
        if let transcript, let source {
            emit(["type": "transcript", "text": transcript, "lang": "fra", "confidence": 1, "speculative": false,
                  "source": source])
        }
        let task = Task { [weak self] in
            // Un temps de « réflexion » réaliste, pour voir l'état et le logo.
            await self?.pause(reply == nil ? 300 : 1400)
            guard let self, !Task.isCancelled else { return }
            for sentence in reply ?? [] {
                self.emit(["type": "reply_text", "utterance_id": id, "text": sentence, "lang": "fra"])
                await self.pause(350)
                if Task.isCancelled { return }
            }
            self.lock.withLock { self.speaking = id }
            self.emit(["type": "tts_start", "utterance_id": id, "latency_ms": 0, "sample_rate": 16_000])
            for chunk in DemoEngineTransport.testTone() {
                guard !Task.isCancelled else { return }
                self.emitAudio(chunk)
                await self.pause(60)  // ~ 3 trames de 20 ms : la lecture démarre vite
            }
            guard !Task.isCancelled else { return }
            // Tour terminé : une interruption arrivée ensuite n'a plus rien à couper.
            self.lock.withLock {
                self.speaking = nil
                if self.utterance == id { self.turn = nil }
            }
            self.emit(["type": "tts_end", "utterance_id": id, "interrupted": false])
            self.emit(["type": "turn_end", "utterance_id": id, "interrupted": false])
        }
        lock.withLock { turn = task }
    }

    private func interrupt() {
        let (task, current, last) = lock.withLock { () -> (Task<Void, Never>?, Int?, Int) in
            let state = (turn, speaking, utterance)
            turn = nil
            speaking = nil
            return state
        }
        guard let task else { return }
        task.cancel()
        emit(["type": "interrupted"])
        if let current { emit(["type": "tts_end", "utterance_id": current, "interrupted": true]) }
        emit(["type": "turn_end", "utterance_id": current ?? last, "interrupted": true])
    }

    private func pause(_ milliseconds: Double) async {
        try? await Task.sleep(for: .milliseconds(milliseconds * timeScale))
    }

    // MARK: Émission

    /// `numbered` : le serveur numérote tous les événements, sauf `ready`, `pong` (et quelques autres) ; même règle ici.
    private func emit(_ event: [String: Any], numbered: Bool = true) {
        var event = event
        let isClosed = lock.withLock { () -> Bool in
            if numbered, !closed {
                seq += 1
                event["seq"] = Int(seq)
            }
            return closed
        }
        guard !isClosed,
              let data = try? JSONSerialization.data(withJSONObject: event),
              let json = String(data: data, encoding: .utf8) else { return }
        output.yield(.text(json))
    }

    private func emitAudio(_ pcm: Data) {
        let frame = lock.withLock { () -> Data? in
            guard !closed else { return nil }
            seq += 1
            return AudioFrame(kind: .tts, seq: seq, payload: pcm).encoded()
        }
        if let frame { output.yield(.binary(frame)) }
    }

    // MARK: Contenu

    static let voiceTranscript = "Message vocal (la démo hors ligne ne reconnaît pas la parole)"

    static let voiceReply = [
        "Démo hors ligne : j'ai bien reçu votre message vocal, mais je ne sais pas encore le comprendre.",
        "Le vrai moteur le transcrira et vous répondra dès qu'il sera en ligne.",
    ]

    static func reply(toText said: String) -> [String] {
        let quoted = said.count > 200 ? String(said.prefix(200)) + "…" : said
        return [
            "Démo hors ligne : vous avez écrit « \(quoted) ».",
            "Le vrai moteur n'est pas encore en ligne ; cette réponse vient de l'iPhone, pour essayer l'interface :",
            "\n\n- **l'historique** et les réponses mises en forme ;\n- **le mode vocal**, le logo animé et la lecture à voix haute.",
        ]
    }

    /// Son de test (comme le moteur aujourd'hui) : six « syllabes » douces de 180 ms, en PCM16 16 kHz mono, découpé en
    /// paquets de 60 ms. Assez varié pour que le niveau de lecture anime le logo.
    static func testTone() -> [Data] {
        let rate = 16_000.0
        var samples: [Int16] = []
        let pitches = [262.0, 294.0, 330.0, 294.0, 349.0, 262.0]
        for pitch in pitches {
            let length = Int(rate * 0.18)
            for n in 0..<length {
                let t = Double(n) / rate
                let envelope = sin(Double.pi * Double(n) / Double(length))  // monte et descend : pas de clic
                samples.append(Int16(0.22 * 32_767 * envelope * sin(2 * Double.pi * pitch * t)))
            }
            samples.append(contentsOf: repeatElement(0, count: Int(rate * 0.08)))
        }
        let chunk = Int(rate * 0.06)
        return stride(from: 0, to: samples.count, by: chunk).map { start in
            let slice = samples[start..<min(start + chunk, samples.count)]
            var data = Data(capacity: slice.count * 2)
            for sample in slice {
                let little = sample.littleEndian
                withUnsafeBytes(of: little) { data.append(contentsOf: $0) }
            }
            return data
        }
    }
}
