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
        #expect(o["vad"] == nil && o["client"] == nil)
    }

    @Test("hello de reprise avec jeton, VAD client et identification")
    func helloResume() throws {
        let hello = ClientMessage.Hello(lang: .auto, sessionID: "abc", lastSeq: 42, token: "t0k", vad: .client,
                                        client: ClientInfo(app: "ave-ios", version: "1.0", sdk: "avekit"))
        let o = try object(.hello(hello))
        #expect(o["session_id"] as? String == "abc")
        #expect(o["last_seq"] as? Int == 42)
        #expect(o["token"] as? String == "t0k")
        #expect(o["vad"] as? String == "client")
        let client = try #require(o["client"] as? [String: Any])
        #expect(client["app"] as? String == "ave-ios" && client["sdk"] as? String == "avekit")
    }

    @Test("messages de contrôle, texte, speak et changement de langue")
    func control() throws {
        #expect(try object(.interrupt)["type"] as? String == "interrupt")
        #expect(try object(.bye)["type"] as? String == "bye")
        #expect(try object(.ping(t: 5))["t"] as? Double == 5)
        let eos = try object(.endOfSpeech(meta: ["transcript": .string("salut")]))
        #expect(eos["type"] as? String == "end_of_speech")
        #expect((eos["meta"] as? [String: Any])?["transcript"] as? String == "salut")
        #expect(try object(.endOfSpeech(meta: nil))["meta"] == nil)
        let text = try object(.text("Où est ma course ?"))
        #expect(text["type"] as? String == "text" && text["text"] as? String == "Où est ma course ?")
        let speak = try object(.speak(text: "bonjour", lang: .french))
        #expect(speak["type"] as? String == "speak" && speak["text"] as? String == "bonjour" && speak["lang"] as? String == "fra")
        #expect(try object(.speak(text: "x", lang: nil))["lang"] == nil)
        let setLang = try object(.setLanguage(.soussou))
        #expect(setLang["type"] as? String == "set_language" && setLang["lang"] as? String == "sus")
    }

    @Test("ready ancien : seq non porté, pas de langues")
    func readyLegacy() throws {
        let f = try ServerFrame.decode(#"{"type":"ready","session_id":"s","resumed":true,"last_mic_seq":9,"seq":4,"protocol":1}"#)
        #expect(f.seq == nil)
        #expect(f.event == .ready(.init(sessionID: "s", resumed: true, lastMicSeq: 9, seq: 4, protocolVersion: 1,
                                        graceSeconds: nil, languages: nil)))
    }

    @Test("ready actuel : grace_s et langues avec disponibilité réelle")
    func readyWithLanguages() throws {
        let json = #"{"type":"ready","session_id":"s","resumed":false,"last_mic_seq":0,"seq":0,"protocol":1,"grace_s":30,"languages":[{"code":"fra","name":"Français","native":"Français","regions":["west_africa"],"status":"production","available":true},{"code":"sus","name":"Soussou","native":"Sosoxui","regions":["west_africa"],"status":"planned","available":false},{"code":"zul","name":"Zoulou","native":"isiZulu","regions":["southern_africa"],"status":"planned","available":null}]}"#
        guard case .ready(let r) = try ServerFrame.decode(json).event else { Issue.record("pas ready"); return }
        #expect(r.graceSeconds == 30)
        let langs = try #require(r.languages)
        #expect(langs.map(\.code) == ["fra", "sus", "zul"])
        #expect(langs.map(\.available) == [true, false, nil])
    }

    @Test("ready réel du serveur : grace_s est un flottant (30.0), une langue mal formée n'empêche pas ready")
    func readyTolerance() throws {
        let real = #"{"type":"ready","session_id":"s","resumed":false,"last_mic_seq":0,"seq":0,"protocol":1,"grace_s":30.0,"languages":[{"code":"bam","name":"Bambara","native":"Bamanankan","regions":["west_africa"],"status":"planned","available":false}]}"#
        guard case .ready(let r) = try ServerFrame.decode(real).event else { Issue.record("pas ready"); return }
        #expect(r.graceSeconds == 30 && r.languages?.count == 1)
        let broken = #"{"type":"ready","session_id":"s","resumed":false,"last_mic_seq":0,"seq":0,"protocol":1,"grace_s":"trente","languages":[{"code":42}]}"#
        guard case .ready(let r2) = try ServerFrame.decode(broken).event else { Issue.record("ready illisible"); return }
        #expect(r2.sessionID == "s" && r2.graceSeconds == nil && r2.languages == nil)
    }

    @Test("transcript voix, provisoire et écho texte")
    func transcripts() throws {
        let voice = try ServerFrame.decode(#"{"type":"transcript","seq":3,"text":"bonjour","lang":"fra","confidence":0.9,"speculative":false,"source":"voice"}"#)
        #expect(voice == ServerFrame(seq: 3, event: .transcript(text: "bonjour", lang: "fra", confidence: 0.9, speculative: false, source: .voice)))
        let spec = try ServerFrame.decode(#"{"type":"transcript","seq":4,"text":"bon","lang":"fra","confidence":0.5,"speculative":true,"source":"voice"}"#)
        guard case .transcript(_, _, _, let speculative, _) = spec.event else { Issue.record("pas transcript"); return }
        #expect(speculative)  // "calculé d'avance", pas provisoire
        let echo = try ServerFrame.decode(#"{"type":"transcript","seq":5,"text":"salut","lang":"fra","confidence":1,"speculative":false,"source":"text"}"#)
        guard case .transcript(_, _, _, _, let source) = echo.event else { Issue.record("pas transcript"); return }
        #expect(source == .text)
    }

    @Test("reply_text, turn_end, tts")
    func replyAndTurn() throws {
        #expect(try ServerFrame.decode(#"{"type":"reply_text","seq":6,"utterance_id":6,"text":"Bonjour.","lang":"fra"}"#)
                == ServerFrame(seq: 6, event: .replyText(utteranceID: 6, text: "Bonjour.", lang: "fra")))
        #expect(try ServerFrame.decode(#"{"type":"turn_end","seq":9,"utterance_id":6,"interrupted":true}"#)
                == ServerFrame(seq: 9, event: .turnEnd(utteranceID: 6, interrupted: true)))
        #expect(try ServerFrame.decode(#"{"type":"tts_start","seq":4,"utterance_id":4,"latency_ms":120,"sample_rate":16000}"#)
                == ServerFrame(seq: 4, event: .ttsStart(utteranceID: 4, sampleRate: 16000, latencyMs: 120)))
        #expect(try ServerFrame.decode(#"{"type":"tts_end","seq":9,"utterance_id":4,"interrupted":false}"#)
                == ServerFrame(seq: 9, event: .ttsEnd(utteranceID: 4, interrupted: false)))
        #expect(try ServerFrame.decode(#"{"type":"interrupted","seq":10}"#) == ServerFrame(seq: 10, event: .interrupted))
    }

    @Test("action : confirm au premier niveau ; absent = confirmation exigée")
    func action() throws {
        let f = try ServerFrame.decode(#"{"type":"action","seq":2,"name":"cancel_ride","args":{"ride":"r1","n":2},"confirm":true}"#)
        guard case .action(let name, let args, let confirm) = f.event else { Issue.record("pas action"); return }
        #expect(name == "cancel_ride" && confirm)
        #expect(args["ride"]?.stringValue == "r1" && args["n"] == .number(2))
        guard case .action(_, _, let noConfirm) = try ServerFrame.decode(#"{"type":"action","seq":3,"name":"x","args":{}}"#).event
        else { Issue.record("pas action"); return }
        #expect(noConfirm)
        guard case .action(_, _, let explicitFalse) = try ServerFrame.decode(#"{"type":"action","seq":4,"name":"x","args":{},"confirm":false}"#).event
        else { Issue.record("pas action"); return }
        #expect(!explicitFalse)
    }

    @Test("turn_error, y compris rate_limited")
    func turnErrors() throws {
        #expect(try ServerFrame.decode(#"{"type":"turn_error","seq":7,"code":"language_unavailable","message":"m","lang":"sus"}"#).event
                == .turnError(code: "language_unavailable", message: "m", lang: "sus", retryAfterSeconds: nil))
        #expect(try ServerFrame.decode(#"{"type":"turn_error","seq":8,"code":"rate_limited","message":"m","retry_after_s":3}"#).event
                == .turnError(code: "rate_limited", message: "m", lang: nil, retryAfterSeconds: 3))
        // un champ optionnel mal typé ne doit pas faire perdre l'erreur de tour
        #expect(try ServerFrame.decode(#"{"type":"turn_error","seq":9,"code":"rate_limited","retry_after_s":"bientôt"}"#).event
                == .turnError(code: "rate_limited", message: "", lang: nil, retryAfterSeconds: nil))
    }

    @Test("événements non numérotés : speech_start/end, language_set, replayed, pong, error")
    func unnumbered() throws {
        #expect(try ServerFrame.decode(#"{"type":"speech_start"}"#) == ServerFrame(seq: nil, event: .speechStart))
        #expect(try ServerFrame.decode(#"{"type":"speech_end"}"#) == ServerFrame(seq: nil, event: .speechEnd))
        #expect(try ServerFrame.decode(#"{"type":"language_set","lang":"fra"}"#).event == .languageSet(lang: "fra"))
        #expect(try ServerFrame.decode(#"{"type":"error","code":"bad_lang","message":"m"}"#).event
                == .error(code: "bad_lang", message: "m"))
        #expect(try ServerFrame.decode(#"{"type":"replayed","count":3,"gap":false}"#).event == .replayed(count: 3, gap: false))
        #expect(try ServerFrame.decode(#"{"type":"pong","t":12}"#).event == .pong(t: 12))
    }

    @Test("type inconnu (dont l'ancien tool_call) : ignoré sans lever")
    func unknown() throws {
        let f = try ServerFrame.decode(#"{"type":"futur_evenement","seq":5,"x":[1,2]}"#)
        #expect(f.event == .unknown(type: "futur_evenement") && f.seq == 5)
        #expect(try ServerFrame.decode(#"{"type":"tool_call","seq":6,"name":"x","args":{}}"#).event == .unknown(type: "tool_call"))
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
