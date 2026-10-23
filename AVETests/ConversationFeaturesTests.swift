import Foundation
import Testing
@testable import AVECore
@testable import AVEKit

@Suite("Historique local")
struct HistoryTests {
    private func conversation(_ title: String, updated: Date, messages: [StoredMessage] = []) -> StoredConversation {
        StoredConversation(title: title, createdAt: updated, updatedAt: updated, languageCode: "fra", messages: messages)
    }

    @Test("titre : première question, une ligne, raccourcie ; conversation vocale sans question écrite")
    func title() {
        let long = String(repeating: "mot ", count: 20)
        #expect(ConversationHistory.title(for: [StoredMessage(role: .user, text: "Bonjour\nla suite")]) == "Bonjour")
        let t = ConversationHistory.title(for: [StoredMessage(role: .assistant, text: "x"), StoredMessage(role: .user, text: long)])
        #expect(t.hasSuffix("…") && t.count <= ConversationHistory.titleLength + 1)
        #expect(ConversationHistory.title(for: []) == "Conversation vocale")
    }

    @Test("regroupement : aujourd'hui, hier, 7 jours, 30 jours, plus ancien ; sections vides retirées")
    func grouping() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Africa/Conakry"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 15)))
        func daysAgo(_ d: Int) throws -> Date { try #require(calendar.date(byAdding: .day, value: -d, to: now)) }
        let items = [conversation("a", updated: now), conversation("b", updated: try daysAgo(1)),
                     conversation("c", updated: try daysAgo(5)), conversation("d", updated: try daysAgo(40))]
        let groups = ConversationHistory.grouped(items, now: now, calendar: calendar)
        #expect(groups.map(\.section) == [.today, .yesterday, .lastWeek, .older])
        #expect(groups.map { $0.items.map(\.title) } == [["a"], ["b"], ["c"], ["d"]])
    }

    @Test("recherche : titres et messages, sans accents ni majuscules")
    func search() {
        let now = Date()
        let items = [conversation("Recette du riz gras", updated: now),
                     conversation("Lettre", updated: now, messages: [StoredMessage(role: .assistant, text: "Écrire à Awa")])]
        #expect(ConversationHistory.search("RIZ", in: items).map(\.title) == ["Recette du riz gras"])
        #expect(ConversationHistory.search("ecrire", in: items).map(\.title) == ["Lettre"])
        #expect(ConversationHistory.search("  ", in: items).count == 2)
    }

    @Test("stockage fichier : enregistrer, relire trié, supprimer une conversation puis tout")
    func fileStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ave-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileConversationStore(directory: dir)
        let older = conversation("ancienne", updated: Date(timeIntervalSince1970: 1_000))
        let newer = conversation("récente", updated: Date(timeIntervalSince1970: 2_000),
                                 messages: [StoredMessage(role: .user, text: "salut")])
        store.save(older)
        store.save(newer)
        #expect(store.list().map(\.title) == ["récente", "ancienne"])
        #expect(store.list().first?.messages == newer.messages)
        store.delete(id: older.id)
        #expect(store.list().map(\.title) == ["récente"])
        store.deleteAll()
        #expect(store.list().isEmpty)
    }

    @Test("fil gardé : sans cartes d'action ni bulles vides ; reprise avec l'avis « sans mémoire »")
    func storedAndRestored() {
        var t = ChatTranscript()
        t.apply(.transcript(text: "Bonjour", lang: "fra", confidence: 1, speculative: false, source: .text))
        t.apply(.replyText(utteranceID: 1, text: "Salut.", lang: "fra"))
        t.apply(.turnEnd(utteranceID: 1, interrupted: false))
        t.apply(.action(name: "rappel", args: [:], confirm: true))
        let stored = ConversationHistory.stored(from: t.messages)
        #expect(stored.map(\.text) == ["Bonjour", "Salut."])
        let restored = ChatTranscript(restoring: stored, notice: UserMessages.resumedWithoutMemory)
        #expect(restored.messages.map(\.text) == ["Bonjour", "Salut.", UserMessages.resumedWithoutMemory])
        #expect(restored.messages.allSatisfy { $0.utteranceID == nil && $0.status == .complete })
        #expect(ChatTranscript(restoring: [], notice: "x").messages.isEmpty)
    }
}

@Suite("Mise en forme des réponses")
struct MarkdownBlocksTests {
    @Test("titres, listes à puces et numérotées, citation, code, paragraphes")
    func parse() {
        let text = """
        # Trois façons
        Voici une **liste** :
        - Merci beaucoup
        * Mille mercis
        1. Premier
        2) Second
        > À retenir

        ```
        let x = 1
        ```
        Fin.
        """
        #expect(MarkdownBlocks.parse(text) == [
            .heading(level: 1, text: "Trois façons"),
            .paragraph("Voici une **liste** :"),
            .bullet("Merci beaucoup"),
            .bullet("Mille mercis"),
            .numbered(index: 1, text: "Premier"),
            .numbered(index: 2, text: "Second"),
            .quote("À retenir"),
            .code("let x = 1"),
            .paragraph("Fin."),
        ])
    }

    @Test("texte simple : un paragraphe ; « #hashtag » et « 2026 était » ne sont ni titre ni liste")
    func plain() {
        #expect(MarkdownBlocks.parse("Bonjour.\nÇa va ?") == [.paragraph("Bonjour.\nÇa va ?")])
        #expect(MarkdownBlocks.parse("#hashtag") == [.paragraph("#hashtag")])
        #expect(MarkdownBlocks.parse("2026 était une année") == [.paragraph("2026 était une année")])
        #expect(MarkdownBlocks.parse("```\ncode non fermé") == [.code("code non fermé")])
    }
}

@MainActor
@Suite("Coordinateur : fonctions de la proposition 2")
struct CoordinatorFeatureTests {
    @Test("micro coupé : la capture s'arrête sans quitter le mode vocal, puis reprend")
    func mute() async throws {
        let h = try Harness()
        _ = try await h.open()
        let starts = h.mic.starts
        await h.coordinator.setMicMuted(true)
        #expect(h.coordinator.micMuted && h.coordinator.mode == .voice && h.mic.stops >= 1)
        await h.coordinator.setMicMuted(false)
        #expect(!h.coordinator.micMuted && h.mic.starts == starts + 1)
        await h.coordinator.stop()
    }

    @Test("lecture automatique coupée en mode texte : rien n'est joué, l'audio est gardé pour « Lire à voix haute »")
    func autoPlayOff() async throws {
        let h = try Harness()
        let t = try await h.open()
        await h.coordinator.setMode(.text)
        h.coordinator.autoPlayInTextMode = false
        await h.coordinator.sendText("salut")
        t.serverSend(#"{"type":"transcript","seq":1,"text":"salut","lang":"fra","confidence":1,"speculative":false,"source":"text"}"#)
        t.serverSend(#"{"type":"reply_text","seq":2,"utterance_id":3,"text":"Salut.","lang":"fra"}"#)
        t.serverSend(#"{"type":"tts_start","seq":3,"utterance_id":3,"latency_ms":0,"sample_rate":16000}"#)
        t.serverSend(audio: 4, Data([1, 1]))
        t.serverSend(#"{"type":"tts_end","seq":5,"utterance_id":3,"interrupted":false}"#)
        t.serverSend(#"{"type":"turn_end","seq":6,"utterance_id":3,"interrupted":false}"#)
        let reply = try #require(await eventuallyValue { h.coordinator.transcript.messages.last(where: { $0.role == .assistant }) })
        #expect(await eventually { await h.coordinator.hasCachedAudio(for: reply.id) })
        #expect(h.player.enqueued.isEmpty)
        await h.coordinator.stop()
    }

    @Test("réessayer : renvoie la question qui précède la réponse")
    func retry() async throws {
        let h = try Harness()
        let t = try await h.open()
        await h.completeTurn(t)  // question « salut », réponse « Bonjour. »
        let reply = try #require(h.coordinator.transcript.messages.last)
        await h.coordinator.retry(messageID: reply.id)
        #expect(await eventually { t.sentJSON.contains { $0["type"] as? String == "text" && $0["text"] as? String == "salut" } })
        await h.coordinator.stop()
    }
}

/// Attend une valeur non nulle (même principe que `eventually`).
@MainActor
func eventuallyValue<T>(_ value: @MainActor () -> T?) async -> T? {
    for _ in 0..<200 {
        if let v = value() { return v }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return nil
}
