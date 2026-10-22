import Foundation
import Testing
@testable import AVECore

@Suite("Messages JSON")
struct MessageCodingTests {
    private func object(_ m: ClientMessage) throws -> [String: Any] {
        let s = try m.jsonString()
        return try #require(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    @Test("hello initial : pas de session_id ni de jeton")
    func helloFresh() throws {
        let o = try object(.hello(.init(lang: .french)))
        #expect(o["type"] as? String == "hello")
        #expect(o["version"] as? Int == 1)
        #expect(o["codec"] as? String == "pcm16")
        #expect(o["lang"] as? String == "fra")
        #expect(o["sample_rate"] as? Int == 16000)
        #expect(o["session_id"] == nil && o["last_seq"] == nil && o["token"] == nil)
    }

    @Test("hello de reprise avec jeton")
    func helloResume() throws {
        let o = try object(.hello(.init(lang: .auto, sessionID: "abc", lastSeq: 42, token: "t0k")))
        #expect(o["session_id"] as? String == "abc")
        #expect(o["last_seq"] as? Int == 42)
        #expect(o["token"] as? String == "t0k")
    }

    @Test("messages de contrôle")
    func control() throws {
        #expect(try object(.interrupt)["type"] as? String == "interrupt")
        #expect(try object(.bye)["type"] as? String == "bye")
        #expect(try object(.ping(t: 5))["t"] as? Double == 5)
        let eos = try object(.endOfSpeech(meta: ["transcript": .string("salut")]))
        #expect(eos["type"] as? String == "end_of_speech")
        #expect((eos["meta"] as? [String: Any])?["transcript"] as? String == "salut")
        #expect(try object(.endOfSpeech(meta: nil))["meta"] == nil)
    }

    @Test("ready : seq non porté (hors numérotation)")
    func ready() throws {
        let f = try ServerFrame.decode(#"{"type":"ready","session_id":"s","resumed":true,"last_mic_seq":9,"seq":4,"protocol":1}"#)
        #expect(f.seq == nil)
        #expect(f.event == .ready(.init(sessionID: "s", resumed: true, lastMicSeq: 9, seq: 4, protocolVersion: 1)))
    }

    @Test("événements séquencés")
    func sequenced() throws {
        let t = try ServerFrame.decode(#"{"type":"transcript","seq":3,"text":"bonjour","lang":"fra","confidence":0.9}"#)
        #expect(t == ServerFrame(seq: 3, event: .transcript(text: "bonjour", lang: "fra", confidence: 0.9)))
        let s = try ServerFrame.decode(#"{"type":"tts_start","seq":4,"utterance_id":4,"latency_ms":120,"sample_rate":16000}"#)
        #expect(s == ServerFrame(seq: 4, event: .ttsStart(utteranceID: 4, sampleRate: 16000, latencyMs: 120)))
        let e = try ServerFrame.decode(#"{"type":"tts_end","seq":9,"utterance_id":4,"interrupted":true}"#)
        #expect(e == ServerFrame(seq: 9, event: .ttsEnd(utteranceID: 4, interrupted: true)))
        let i = try ServerFrame.decode(#"{"type":"interrupted","seq":10}"#)
        #expect(i == ServerFrame(seq: 10, event: .interrupted))
    }

    @Test("tool_call avec arguments imbriqués")
    func toolCall() throws {
        let f = try ServerFrame.decode(#"{"type":"tool_call","seq":2,"name":"order_ride","args":{"utterance":"x","confirm":true,"n":2}}"#)
        guard case .toolCall(let name, let args) = f.event else { Issue.record("mauvais cas"); return }
        #expect(name == "order_ride")
        #expect(args["confirm"]?.boolValue == true)
        #expect(args["utterance"]?.stringValue == "x")
        #expect(args["n"] == .number(2))
    }

    @Test("erreur, replayed, pong")
    func misc() throws {
        #expect(try ServerFrame.decode(#"{"type":"error","code":"bad_lang","message":"m"}"#).event
                == .error(code: "bad_lang", message: "m"))
        #expect(try ServerFrame.decode(#"{"type":"replayed","count":3,"gap":false}"#).event
                == .replayed(count: 3, gap: false))
        #expect(try ServerFrame.decode(#"{"type":"pong","t":12}"#).event == .pong(t: 12))
    }

    @Test("type inconnu : ignoré sans lever")
    func unknown() throws {
        let f = try ServerFrame.decode(#"{"type":"futur_evenement","seq":5,"x":[1,2]}"#)
        #expect(f.event == .unknown(type: "futur_evenement"))
        #expect(f.seq == 5)
    }

    @Test("type connu mal formé : lève malformedEvent")
    func malformed() {
        #expect(throws: AVEProtocolError.malformedEvent(type: "tts_start")) {
            try ServerFrame.decode(#"{"type":"tts_start","seq":1}"#)
        }
    }

    @Test("JSON invalide : lève")
    func garbage() {
        #expect(throws: (any Error).self) { try ServerFrame.decode("pas du json") }
    }
}
