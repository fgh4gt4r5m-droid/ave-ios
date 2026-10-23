import Foundation
import Testing
@testable import AVECore
@testable import AVEKit

/// Moteur de démo hors ligne : il doit parler le VRAI protocole, pour que l'app soit exercée comme avec le serveur.
@Suite("Moteur de démo hors ligne")
struct DemoEngineTransportTests {
    /// Lit les messages jusqu'à `turn_end` (ou `limit` messages) et les décode.
    private func collect(_ transport: DemoEngineTransport, limit: Int = 200) async throws -> [ServerFrame] {
        var frames: [ServerFrame] = []
        var count = 0
        for try await message in transport.incoming {
            count += 1
            if case .text(let json) = message {
                let frame = try ServerFrame.decode(json)
                frames.append(frame)
                if case .turnEnd = frame.event { break }
            }
            if count >= limit { break }
        }
        return frames
    }

    private func send(_ transport: DemoEngineTransport, _ message: ClientMessage) async throws {
        try await transport.send(.text(try message.jsonString()))
    }

    @Test("hello : ready, avec le français seul disponible")
    func helloGivesReady() async throws {
        let transport = DemoEngineTransport(timeScale: 0)
        try await send(transport, .hello(.init(lang: .french)))
        var iterator = transport.incoming.makeAsyncIterator()
        guard case .text(let json) = try await iterator.next() else { Issue.record("pas de ready"); return }
        guard case .ready(let ready) = try ServerFrame.decode(json).event else { Issue.record("pas de ready"); return }
        #expect(!ready.resumed)
        #expect(ready.languages?.map(\.code) == ["fra"])
        #expect(ready.learning == nil)  // pas de demande d'aide à l'amélioration dans la démo
    }

    @Test("texte : écho annoncé, réponse en plusieurs phrases, voix de test, fin de tour, dans l'ordre")
    func textTurn() async throws {
        let transport = DemoEngineTransport(timeScale: 0)
        try await send(transport, .text("Bonjour"))
        let frames = try await collect(transport)
        let types = frames.map { "\($0.event)".prefix(while: { $0 != "(" }) }
        #expect(types.first == "transcript")
        #expect(types.suffix(2) == ["ttsEnd", "turnEnd"])
        guard case .transcript(let text, _, _, _, let source) = frames[0].event else { Issue.record("écho"); return }
        #expect(text == "Bonjour")
        #expect(source == .text)
        let replies = frames.compactMap { frame -> String? in
            if case .replyText(_, let text, _) = frame.event { return text } else { return nil }
        }
        #expect(replies.first?.hasPrefix("Démo hors ligne") == true)
        // Numérotation strictement croissante : le client écarte tout doublon.
        let seqs = frames.compactMap(\.seq)
        #expect(seqs == seqs.sorted() && Set(seqs).count == seqs.count)
    }

    @Test("message vocal : signalé comme tel, jamais « transcrit »")
    func voiceTurnIsHonest() async throws {
        let transport = DemoEngineTransport(timeScale: 0)
        try await send(transport, .endOfSpeech(meta: nil))
        let frames = try await collect(transport)
        guard case .transcript(let text, _, _, _, let source) = frames.first?.event else { Issue.record("écho"); return }
        #expect(source == .voice)
        #expect(text == DemoEngineTransport.voiceTranscript)
    }

    @Test("lecture à voix haute (speak) : la voix seule, close par turn_end, sans nouvelle réponse écrite")
    func speakTurn() async throws {
        let transport = DemoEngineTransport(timeScale: 0)
        try await send(transport, .speak(text: "Salut", lang: nil))
        let frames = try await collect(transport)
        #expect(!frames.contains { if case .replyText = $0.event { true } else { false } })
        #expect(!frames.contains { if case .transcript = $0.event { true } else { false } })
        #expect(frames.contains { if case .ttsStart = $0.event { true } else { false } })
    }

    @Test("son de test : PCM16 mono, paquets de 60 ms, pas vide")
    func testToneShape() {
        let chunks = DemoEngineTransport.testTone()
        #expect(!chunks.isEmpty)
        #expect(chunks.dropLast().allSatisfy { $0.count == 960 * 2 })  // 60 ms à 16 kHz = 960 échantillons
        #expect(chunks.contains { chunk in chunk.contains { $0 != 0 } })
    }

    @Test("ping : pong, sans numéro")
    func pingPong() async throws {
        let transport = DemoEngineTransport(timeScale: 0)
        try await send(transport, .ping(t: 42))
        var iterator = transport.incoming.makeAsyncIterator()
        guard case .text(let json) = try await iterator.next() else { Issue.record("pas de pong"); return }
        let frame = try ServerFrame.decode(json)
        #expect(frame.seq == nil)
        #expect(frame.event == .pong(t: 42))
    }
}
