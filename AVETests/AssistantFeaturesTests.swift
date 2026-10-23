import Foundation
import Testing
@testable import AVECore
@testable import AVEKit

// Assistant du quotidien (maquettes validées le 2026-10-23) : mention selon `ready.engine` (D6), tableaux, « Arrêter ».

@Suite("Assistant : mention selon l'état du moteur (D6)")
struct EngineNoticeTests {
    /// Vecteurs « D6, … » du contrat (`contrat/vectors.json`, moteur `main` @ `a328fae`), sans les champs déjà testés.
    private func engine(_ json: String) throws -> EngineStatus? {
        let frame = try ServerFrame.decode(#"{"type":"ready","session_id":"s_d6","resumed":false,"last_mic_seq":0,"seq":0,"protocol":1,"grace_s":30.0\#(json)}"#)
        guard case .ready(let ready) = frame.event else {
            Issue.record("pas ready")
            return nil
        }
        return ready.engine
    }

    @Test("tout réel : aucune mention")
    func allReal() throws {
        let e = try engine(#","engine":{"dialogue":"real","voice":"real","images":"real","documents":"real"}"#)
        #expect(e == EngineStatus(dialogue: .real, voice: .real, images: .real, documents: .real))
        #expect(UserMessages.demoNotice(engine: e, fallback: UserMessages.demoEngine) == nil)
    }

    @Test("tout écho (moteur en ligne au 2026-10-23) : mention complète")
    func allEcho() throws {
        let e = try engine(#","engine":{"dialogue":"echo","voice":"test_tone","images":"simulated","documents":"simulated"}"#)
        #expect(e?.voice == .testTone && e?.images == .simulated)
        #expect(UserMessages.demoNotice(engine: e, fallback: nil) == UserMessages.demoEngine)
    }

    @Test("mixte : dialogue réel, voix de test → seule la voix est annoncée")
    func mixed() throws {
        let e = try engine(#","engine":{"dialogue":"real","voice":"test_tone","images":"simulated","documents":"real"}"#)
        #expect(UserMessages.demoNotice(engine: e, fallback: UserMessages.demoEngine)
                == "Version d'essai : la voix de l'assistant est un son de test.")
    }

    @Test("fonctions non activées : off ; ancien moteur sans engine : repli sur le réglage du build")
    func offAndLegacy() throws {
        let off = try engine(#","engine":{"dialogue":"real","voice":"real","images":"off","documents":"off"}"#)
        #expect(off?.images == .off && off?.documents == .off)
        let legacy = try engine("")
        #expect(legacy == nil)
        #expect(UserMessages.demoNotice(engine: legacy, fallback: UserMessages.demoEngine) == UserMessages.demoEngine)
        #expect(UserMessages.demoNotice(engine: legacy, fallback: nil) == nil)
    }

    @Test("valeur inconnue : lue comme « pas réel », la mention reste ; engine mal formé : ready lu quand même")
    func unknownValues() throws {
        let e = try engine(#","engine":{"dialogue":"llm-v2","voice":"real"}"#)
        #expect(e?.dialogue == nil && e?.images == nil)
        #expect(UserMessages.demoNotice(engine: e, fallback: nil) == "Version d'essai : l'assistant répète ce que vous dites.")
        #expect(try engine(#","engine":"oui""#) == nil)
    }
}

@Suite("Assistant : tableaux dans les réponses")
struct MarkdownTableTests {
    @Test("tableau simple : en-tête, séparateur, lignes ; cellules complétées à la largeur de l'en-tête")
    func table() {
        let text = """
        ### Menu simple
        | Jour | Midi | Soir |
        |------|:----:|-----:|
        | Lundi | Riz, sauce feuille | Soupe |
        | Mardi | Reste de riz |
        **Astuce :** cuisinez deux portions.
        """
        #expect(MarkdownBlocks.parse(text) == [
            .heading(level: 3, text: "Menu simple"),
            .table(header: ["Jour", "Midi", "Soir"],
                   rows: [["Lundi", "Riz, sauce feuille", "Soupe"], ["Mardi", "Reste de riz", ""]]),
            .paragraph("**Astuce :** cuisinez deux portions."),
        ])
    }

    @Test("sans ligne de séparation (réponse encore en cours d'écriture) : reste du texte")
    func incomplete() {
        #expect(MarkdownBlocks.parse("| Jour | Midi |") == [.paragraph("| Jour | Midi |")])
        #expect(MarkdownBlocks.parse("| Jour | Midi |\n|---|---|") == [.table(header: ["Jour", "Midi"], rows: [])])
        #expect(MarkdownBlocks.isSeparator("|---|:--:|") && !MarkdownBlocks.isSeparator("| a | b |"))
    }

    @Test("une barre dans un bloc de code n'ouvre pas de tableau")
    func codeKeepsPipes() {
        #expect(MarkdownBlocks.parse("```\n| a | b |\n|---|---|\n```") == [.code("| a | b |\n|---|---|")])
    }
}

@Suite("Assistant : arrêter une réponse")
struct StopResponseTests {
    @Test("machine : Arrêter pendant la réflexion prévient le moteur, sans purge")
    func machineThinking() {
        var m = BargeInStateMachine()
        _ = m.handle(.userSentText)
        #expect(m.phase == .thinking)
        #expect(m.handle(.manualInterrupt) == [.sendInterrupt])
        #expect(m.phase == .idle)
    }

    @MainActor
    @Test("session : interrupt envoyé, bulle « Interrompu », reliquat du tour ignoré jusqu'à son turn_end")
    func session() async throws {
        let h = try Harness()
        let t = try await h.open()
        let c = h.coordinator
        await c.sendText("Fais-moi un budget")
        #expect(c.isResponding)
        t.serverSend(#"{"type":"transcript","seq":1,"text":"Fais-moi un budget","lang":"fra","confidence":1,"speculative":false,"source":"text"}"#)
        t.serverSend(#"{"type":"reply_text","seq":2,"utterance_id":7,"text":"Voici une méthode.","lang":"fra"}"#)
        #expect(await eventually { await c.transcript.messages.last?.text == "Voici une méthode." })

        await c.stopResponse()
        #expect(t.sentJSON.contains { $0["type"] as? String == "interrupt" })
        #expect(c.transcript.messages.last?.status == .interrupted)
        #expect(!c.isResponding)

        // Ce qui était déjà parti du moteur n'est pas affiché ; l'ordre du moteur : turn_end puis interrupted.
        t.serverSend(#"{"type":"reply_text","seq":3,"utterance_id":7,"text":"Étape 2.","lang":"fra"}"#)
        t.serverSend(#"{"type":"turn_end","seq":4,"utterance_id":7,"interrupted":true}"#)
        t.serverSend(#"{"type":"interrupted","seq":5}"#)
        await settle()
        #expect(c.transcript.messages.last?.text == "Voici une méthode.")
        #expect(!c.transcript.messages.contains { $0.text.contains("Étape 2") })

        // Le tour suivant s'affiche normalement.
        await c.sendText("Merci")
        t.serverSend(#"{"type":"transcript","seq":6,"text":"Merci","lang":"fra","confidence":1,"speculative":false,"source":"text"}"#)
        t.serverSend(#"{"type":"reply_text","seq":7,"utterance_id":8,"text":"Avec plaisir.","lang":"fra"}"#)
        #expect(await eventually { await c.transcript.messages.last?.text == "Avec plaisir." })
        await c.stop()
    }
}
