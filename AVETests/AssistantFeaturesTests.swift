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

    /// Vecteur « D11, retouche et prolongement retirés par l'exploitant » (moteur `main` @ `8685cd5`, PR #36).
    @Test("D11 : image_tasks dit quelles tâches d'image proposer ; absent = toutes ; valeur inconnue ignorée")
    func imageTasks() throws {
        let cut = try engine(#","engine":{"dialogue":"real","voice":"real","images":"real","documents":"real","image_tasks":["image_generate","image_upscale"]}"#)
        #expect(cut?.imageTasks == [.generate, .upscale])
        #expect(cut?.offers(.generate) == true && cut?.offers(.upscale) == true)
        #expect(cut?.offers(.edit) == false && cut?.offers(.extend) == false)

        let legacy = try engine(#","engine":{"dialogue":"real","voice":"real","images":"real","documents":"real"}"#)
        #expect(legacy?.imageTasks == nil)
        #expect(EngineStatus.ImageTask.allCases.allSatisfy { legacy?.offers($0) == true })

        let off = try engine(#","engine":{"dialogue":"real","voice":"real","images":"off","documents":"off","image_tasks":[]}"#)
        #expect(EngineStatus.ImageTask.allCases.allSatisfy { off?.offers($0) == false })

        let future = try engine(#","engine":{"dialogue":"real","images":"real","image_tasks":["image_generate","video_generate"]}"#)
        #expect(future?.imageTasks == [.generate])
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

@Suite("Écrans épurés : lumière douce")
struct GlowLevelTests {
    @Test("jamais de flash : plancher et plafond bas, paliers de 5 %, fixe avec « Réduire les animations »")
    func bounds() {
        #expect(GlowLevel.edge(level: 0, reduceMotion: false) == 0.2)
        #expect(GlowLevel.edge(level: 1, reduceMotion: false) <= 0.8)
        #expect(GlowLevel.edge(level: 5, reduceMotion: false) <= 0.8)    // niveau aberrant : borné
        #expect(GlowLevel.edge(level: -1, reduceMotion: false) == 0.2)
        #expect(GlowLevel.edge(level: 0.9, reduceMotion: true) == 0.35)
        #expect(GlowLevel.halo(level: 1, reduceMotion: false) <= 0.6)
        #expect(GlowLevel.halo(level: 0.5, reduceMotion: true) == 0.3)
        for step in 0...20 {
            let value = GlowLevel.edge(level: Float(step) / 20, reduceMotion: false)
            #expect(abs(value * 20 - (value * 20).rounded()) < 1e-9)
        }
    }
}

@Suite("Assistant : forme des réponses de Gemma (moteur en ligne, 2026-10-24)")
struct GemmaFormatTests {
    /// Puces « *   » (une étoile, trois espaces) et titres en gras, relevés par la session moteur sur une vraie réponse.
    @Test("puces « *   » lues comme des puces, le gras reste en ligne, « ** » en tête n'est pas une puce")
    func gemmaBullets() {
        let text = "**Trois conseils :**\n*   **Budget :** notez vos dépenses.\n*   Comparez les prix."
        #expect(MarkdownBlocks.parse(text) == [
            .paragraph("**Trois conseils :**"),
            .bullet("**Budget :** notez vos dépenses."),
            .bullet("Comparez les prix."),
        ])
    }
}

@Suite("Assistant : écriture fluide de la réponse")
struct StreamRevealTests {
    @Test("rattrape le texte reçu par cinquièmes, au moins trois caractères, sans le dépasser")
    func cadence() {
        #expect(StreamReveal.next(shown: 0, total: 60) == 12)
        #expect(StreamReveal.next(shown: 58, total: 60) == 60)
        #expect(StreamReveal.next(shown: 59, total: 60) == 60)
        #expect(StreamReveal.next(shown: 60, total: 60) == 60)
        #expect(StreamReveal.next(shown: 70, total: 60) == 60)
    }

    @Test("un fragment de 120 caractères apparaît en moins d'une demi-seconde (15 images à 33 ms)")
    func catchesUp() {
        var shown = 0
        var frames = 0
        while shown < 120 {
            shown = StreamReveal.next(shown: shown, total: 120)
            frames += 1
        }
        #expect(frames <= 15)
        #expect(frames >= 5)  // et pas d'un coup : c'est ce qui rend l'écriture fluide
    }
}

@Suite("Assistant : défilement après l'envoi")
struct LastTurnTests {
    @Test("le dernier échange commence à la dernière question de la personne")
    func lastTurn() {
        var t = ChatTranscript()
        #expect(t.lastTurnStart == 0)
        t.appendUserRequest("Comment économiser ?")
        t.apply(.replyText(utteranceID: 1, text: "Trois idées.", lang: "fra"))
        t.apply(.turnEnd(utteranceID: 1, interrupted: false))
        t.appendUserRequest("Et l'électricité ?")
        #expect(t.lastTurnStart == t.messages.count - 1)
        t.apply(.replyText(utteranceID: 2, text: "Éteignez…", lang: "fra"))
        #expect(t.lastTurnStart == t.messages.count - 2)
    }
}
