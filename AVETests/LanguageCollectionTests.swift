import Foundation
import Testing
@testable import AVECore
@testable import AVEKit

// Apprendre nos langues (D13, D14 ; moteur `main` @ 7a006b3, PR #41 ; maquette validée le 2026-10-24).

@Suite("Apprendre nos langues : la phrase dite dans une langue pas encore transcrite (D13)")
struct LanguageCollectionTests {
    @Test("turn_error porte utterance_id et collected ; absent : moteur antérieur")
    func decoding() throws {
        let kept = try ServerFrame.decode(#"{"type":"turn_error","seq":9,"code":"language_unavailable","message":"m","lang":"sus","utterance_id":5,"collected":true}"#)
        #expect(kept.event == .turnError(code: "language_unavailable", message: "m", lang: "sus", retryAfterSeconds: nil,
                                         utteranceID: 5, collected: true))
        let legacy = try ServerFrame.decode(#"{"type":"turn_error","seq":9,"code":"language_unavailable","message":"m","lang":"sus"}"#)
        #expect(legacy.event == .turnError(code: "language_unavailable", message: "m", lang: "sus", retryAfterSeconds: nil))
    }

    @Test("gardée : « Écrire ma phrase », puis la phrase et le merci ; pas gardée : on le dit ; sinon le message habituel")
    func transcript() {
        var t = ChatTranscript()
        t.apply(.turnError(code: "language_unavailable", message: "", lang: "sus", retryAfterSeconds: nil,
                           utteranceID: 5, collected: true))
        let kept = t.messages.last
        #expect(kept?.role == .system && kept?.text == "Phrase dite en soussou")
        #expect(kept?.collection == SpokenCollection(utteranceID: 5, languageName: "Soussou", state: .awaitingText))
        t.recordSpokenText(messageID: kept?.id ?? -1, text: "Ntan nu nde fe")
        #expect(t.messages.last?.collection?.state == .sent("Ntan nu nde fe"))

        t.apply(.turnError(code: "language_unavailable", message: "", lang: "ful", retryAfterSeconds: nil, utteranceID: 6,
                           collected: false))
        #expect(t.messages.last?.collection?.state == .notKept)
        #expect(UserMessages.collectionNotKept(language: "Peul (Pular)").contains("Aider AVE à s'améliorer"))

        // Vecteur « D13, voix non recueillie » (PR #44) : français pris en charge, phrase non comprise, rien de gardé :
        // le message habituel, jamais « ne comprend pas encore le français ».
        t.apply(.turnError(code: "asr_failed", message: "", lang: "fra", retryAfterSeconds: nil, utteranceID: 1,
                           collected: false))
        #expect(t.messages.last?.collection == nil)
        #expect(t.messages.last?.text == UserMessages.turnError(code: "asr_failed"))
        // Gardée, en français : « mieux comprendre », pas « apprendre ».
        t.apply(.turnError(code: "asr_failed", message: "", lang: "fra", retryAfterSeconds: nil, utteranceID: 2,
                           collected: true))
        #expect(t.messages.last?.collection?.languageUnsupported == false)
        #expect(UserMessages.collectionThanks(language: "Français", unsupported: false)
                == "Merci : votre phrase aidera AVE à mieux comprendre le français.")
        #expect(UserMessages.collectionThanks(language: "Soussou") == "Merci : votre phrase aidera AVE à apprendre le soussou.")

        // Un tour écrit, ou un moteur antérieur : le message habituel, rien à écrire.
        t.apply(.turnError(code: "language_unavailable", message: "", lang: "sus", retryAfterSeconds: nil))
        #expect(t.messages.last?.collection == nil)
        #expect(t.messages.last?.text == UserMessages.turnError(code: "language_unavailable"))
    }
}

@MainActor
@Suite("Apprendre nos langues : session")
struct LanguageCollectionSessionTests {
    @Test("la phrase écrite part en feedback rattaché à la voix, une seule fois")
    func sending() async throws {
        let h = try Harness()
        let t = try await h.open(learning: #"{"available":true,"enabled":true,"notice_version":"2026-10-v1"}"#)
        t.serverSend(#"{"type":"turn_error","seq":3,"code":"language_unavailable","message":"","lang":"sus","utterance_id":5,"collected":true}"#)
        #expect(await eventually { await h.coordinator.pendingCollectionID != nil })
        let id = try #require(h.coordinator.pendingCollectionID)
        await h.coordinator.sendSpokenText(messageID: id, text: "  Ntan nu nde fe ")
        #expect(await eventually { t.sentJSON.contains { $0["type"] as? String == "feedback" } })
        let sent = try #require(t.sentJSON.last { $0["type"] as? String == "feedback" })
        #expect(sent["utterance_id"] as? Int == 5 && sent["rating"] as? String == "down")
        #expect(sent["correction"] as? String == "Ntan nu nde fe")
        #expect(h.coordinator.pendingCollectionID == nil)
        await h.coordinator.sendSpokenText(messageID: id, text: "encore")
        try await Task.sleep(for: .milliseconds(50))
        #expect(t.sentJSON.filter { $0["type"] as? String == "feedback" }.count == 1)
    }
}

@Suite("Écoute d'essai (D14)")
struct ListeningNoticeTests {
    /// Vecteur « D14, dialogue et voix réels mais écoute de test » du contrat.
    @Test("écoute de test : mention d'essai, seule ou ajoutée aux autres ; absente : rien de nouveau")
    func listening() throws {
        let frame = try ServerFrame.decode(#"{"type":"ready","session_id":"s","resumed":false,"last_mic_seq":0,"seq":0,"protocol":1,"engine":{"listening":"test","dialogue":"real","voice":"real","images":"real","documents":"real","image_tasks":["image_generate"],"image_from_chat":false}}"#)
        guard case .ready(let ready) = frame.event else { Issue.record("pas ready"); return }
        #expect(ready.engine?.listening == .test)
        #expect(UserMessages.demoNotice(engine: ready.engine, fallback: nil) == UserMessages.demoListening)

        let echo = EngineStatus(dialogue: .echo, voice: .real, images: nil, documents: nil, listening: .test)
        #expect(UserMessages.demoNotice(engine: echo, fallback: nil)
                == "Version d'essai : l'assistant répète ce que vous dites. En mode vocal, il ne comprend pas encore ce que vous dites.")
        let real = EngineStatus(dialogue: .real, voice: .real, images: nil, documents: nil, listening: .real)
        #expect(UserMessages.demoNotice(engine: real, fallback: nil) == nil)
    }
}
