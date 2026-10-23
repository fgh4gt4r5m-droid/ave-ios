import Foundation
import Testing
@testable import AVECore
@testable import AVEKit

// Réponse au fil de l'eau (D7) et contexte d'une conversation rouverte (D9), moteur `main` @ `d14a002`.

@Suite("D7 et D9 : vecteurs du contrat")
struct StreamingContextVectorTests {
    private func object(_ m: ClientMessage) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(m.jsonString().utf8)) as? [String: Any])
    }

    @Test("hello avec text_delta ; sans demande, pas de champ output (défaut du serveur)")
    func helloOutput() throws {
        let hello = ClientMessage.Hello(lang: .french, token: "t1.x", vad: .client, output: ["text", "text_delta"])
        #expect(try object(.hello(hello))["output"] as? [String] == ["text", "text_delta"])
        #expect(try object(.hello(.init(lang: .french)))["output"] == nil)
    }

    @Test("context : messages avec rôle et texte (vecteur « D9, context »)")
    func context() throws {
        let o = try object(.context([
            ContextMessage(role: .user, text: "Comment payer ma facture d'électricité ?"),
            ContextMessage(role: .assistant, text: "Vous pouvez payer :\n\n- en agence ;\n- par mobile money."),
        ]))
        #expect(o["type"] as? String == "context")
        let messages = try #require(o["messages"] as? [[String: Any]])
        #expect(messages.count == 2 && messages[0]["role"] as? String == "user")
        #expect(messages[1]["text"] as? String == "Vous pouvez payer :\n\n- en agence ;\n- par mobile money.")
    }

    @Test("reply_text exact, reply_delta numéroté, context_ack non numéroté, error bad_context")
    func events() throws {
        let text = try ServerFrame.decode(#"{"type":"reply_text","seq":21,"utterance_id":3,"text":"## Étapes\n\n1. ","lang":"fra"}"#)
        #expect(text.event == .replyText(utteranceID: 3, text: "## Étapes\n\n1. ", lang: "fra"))
        let delta = try ServerFrame.decode(#"{"type":"reply_delta","seq":20,"utterance_id":3,"text":"## Étap"}"#)
        #expect(delta.seq == 20 && delta.event == .replyDelta(utteranceID: 3, text: "## Étap"))
        let ack = try ServerFrame.decode(#"{"type":"context_ack","kept":2,"dropped":0}"#)
        #expect(ack.seq == nil && ack.event == .contextAck(kept: 2, dropped: 0))
        let error = try ServerFrame.decode(#"{"type":"error","code":"bad_context","message":"context : seulement juste après un ready neuf, avant toute entrée"}"#)
        guard case .error(let code, _) = error.event else {
            Issue.record("pas error")
            return
        }
        #expect(code == "bad_context")
    }
}

@Suite("D7 : assemblage de la réponse")
struct StreamingTranscriptTests {
    @Test("reply_text exacts : concaténés sans rien ajouter, le Markdown reste intact")
    func exactText() {
        var t = ChatTranscript()
        t.apply(.replyText(utteranceID: 3, text: "## Étapes\n\n1. ", lang: "fra"))
        t.apply(.replyText(utteranceID: 3, text: "Notez vos revenus.\n2. ", lang: "fra"))
        t.apply(.replyText(utteranceID: 3, text: "Listez les dépenses.", lang: "fra"))
        #expect(t.messages.last?.text == "## Étapes\n\n1. Notez vos revenus.\n2. Listez les dépenses.")
        #expect(MarkdownBlocks.parse(t.messages.last?.text ?? "").count == 3)
    }

    @Test("avec fragments : on affiche les reply_delta, et les reply_text du même tour ne s'ajoutent pas")
    func deltasWin() {
        var t = ChatTranscript()
        t.apply(.replyDelta(utteranceID: 4, text: "## Étap"))
        t.apply(.replyDelta(utteranceID: 4, text: "es\n\n1. "))
        t.apply(.replyText(utteranceID: 4, text: "## Étapes\n\n1. ", lang: "fra"))
        t.apply(.replyDelta(utteranceID: 4, text: "Notez."))
        #expect(t.messages.count == 1)
        #expect(t.messages[0].text == "## Étapes\n\n1. Notez.")
        #expect(t.messages[0].status == .streaming)
        // Un autre tour sans fragments reste affiché par ses reply_text.
        t.apply(.turnEnd(utteranceID: 4, interrupted: false))
        t.apply(.replyText(utteranceID: 5, text: "Bonjour.", lang: "fra"))
        #expect(t.messages.last?.text == "Bonjour.")
    }

    @Test("un fragment remplace la bulle « réponse vocale » du même tour")
    func deltaAfterVoiceOnly() {
        var t = ChatTranscript()
        t.apply(.ttsStart(utteranceID: 6, sampleRate: 16000, latencyMs: 0))
        t.apply(.replyDelta(utteranceID: 6, text: "Voici"))
        #expect(t.messages.count == 1 && t.messages[0].text == "Voici" && !t.messages[0].isVoiceOnly)
    }
}

@Suite("D9 : contexte d'une conversation rouverte")
struct ConversationContextTests {
    private func message(_ role: ChatMessage.Role, _ text: String, id: Int) -> ChatMessage {
        ChatMessage(id: id, role: role, text: text, status: .complete, utteranceID: nil, isVoiceOnly: false, card: nil)
    }

    @Test("seulement les échanges lisibles : pas d'avis de l'app, de carte, de bulle vocale ni de texte vide")
    func filters() {
        var voice = message(.assistant, "", id: 3)
        voice.isVoiceOnly = true
        let card = ChatMessage(id: 4, role: .assistant, text: "", status: .complete, utteranceID: nil, isVoiceOnly: false,
                               card: ActionCard(name: "x", args: [:], requiresConfirmation: true, status: .confirmed))
        let messages = ConversationContext.messages(from: [
            message(.user, "  Bonjour  ", id: 1), message(.system, "Avis", id: 2), voice, card,
            message(.assistant, "Bonjour, que faisons-nous ?", id: 5),
        ])
        #expect(messages == [ContextMessage(role: .user, text: "Bonjour"),
                             ContextMessage(role: .assistant, text: "Bonjour, que faisons-nous ?")])
    }

    @Test("bornes du moteur : 20 messages, 4000 caractères chacun, 8000 en tout, les plus récents gardés")
    func limits() {
        let many = (1...30).map { message($0 % 2 == 0 ? .assistant : .user, "m\($0)", id: $0) }
        let kept = ConversationContext.messages(from: many)
        #expect(kept.count == 20 && kept.first?.text == "m11" && kept.last?.text == "m30")

        let long = String(repeating: "a", count: 5000)
        let trimmed = ConversationContext.messages(from: [message(.user, long, id: 1), message(.assistant, long, id: 2),
                                                          message(.user, "fin", id: 3)])
        #expect(trimmed.allSatisfy { $0.text.count <= 4000 })
        #expect(trimmed.reduce(0) { $0 + $1.text.count } <= 8000)
        #expect(trimmed.last?.text == "fin" && trimmed.count == 2)
        #expect(ConversationContext.messages(from: []).isEmpty)
    }
}

@Suite("D7 et D9 : client WebSocket")
struct StreamingContextClientTests {
    private func makeClient(_ factory: FakeTransportFactory, textDelta: Bool = true) throws -> AVEWebSocketClient {
        let url = try #require(URL(string: "wss://ave.test/v1/stream"))
        let config = AVEWebSocketClient.Configuration(
            endpoint: try AVEEndpoint(url), lang: .french,
            backoff: Backoff(initial: .milliseconds(5), maximum: .milliseconds(20)),
            pingInterval: .seconds(3600), deadPeerTimeout: nil, textDelta: textDelta)
        return AVEWebSocketClient(configuration: config, tokenProvider: { nil }, transportFactory: factory.factory)
    }

    @Test("text_delta demandé dans hello ; refusé par un moteur ancien (bad_output) : reconnexion sans, pas d'échec")
    func textDeltaFallback() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(f)
        let rec = EventRecorder.record(client.events)
        await client.start()
        let t0 = try #require(await f.waitForTransport(0))
        #expect(await eventually { !t0.sentJSON.isEmpty })
        #expect((t0.sentJSON[0]["output"] as? [String])?.contains("text_delta") == true)
        t0.serverSend(#"{"type":"error","code":"bad_output","message":"x"}"#)
        t0.serverDrop()
        let t1 = try #require(await f.waitForTransport(1))
        #expect(await eventually { !t1.sentJSON.isEmpty })
        #expect(t1.sentJSON[0]["output"] == nil)
        t1.serverReady()
        #expect(await eventually { await rec.states.contains(.open(resumed: false)) })
        #expect(!(await rec.states.contains { if case .failed = $0 { true } else { false } }))
        await client.stop()
    }

    @Test("context envoyé juste après un ready neuf, avant le texte ; pas après une reprise")
    func contextOrder() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(f, textDelta: false)
        await client.setContextProvider { [ContextMessage(role: .user, text: "Bonjour")] }
        await client.start()
        let t0 = try #require(await f.waitForTransport(0))
        t0.serverReady(session: "s1")
        #expect(await eventually { await client.isReadyState })
        #expect(await client.sendText("Et ensuite ?"))
        #expect(t0.sentTrace == ["hello", "context", "text"])
        // Reprise de la même session : le moteur a déjà le contexte.
        t0.serverDrop()
        let t1 = try #require(await f.waitForTransport(1))
        t1.serverReady(session: "s1", resumed: true)
        #expect(await eventually { await client.isReadyState })
        #expect(!t1.sentTrace.contains("context"))
        await client.stop()
    }

    @Test("context refusé (bad_context) : reconnexion sans contexte, un seul signal pour l'app")
    func contextFallback() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(f, textDelta: false)
        let rec = EventRecorder.record(client.events)
        await client.setContextProvider { [ContextMessage(role: .user, text: "Bonjour")] }
        await client.start()
        let t0 = try #require(await f.waitForTransport(0))
        t0.serverReady(session: "s1")
        #expect(await eventually { t0.sentTrace.contains("context") })
        t0.serverSend(#"{"type":"error","code":"unknown_type","message":"context"}"#)
        t0.serverDrop()
        let t1 = try #require(await f.waitForTransport(1))
        t1.serverReady(session: "s2")
        #expect(await eventually { await client.isReadyState })
        #expect(!t1.sentTrace.contains("context"))
        #expect(await rec.serverEvents.contains(.error(code: "bad_context", message: "")))
        await client.stop()
    }
}
