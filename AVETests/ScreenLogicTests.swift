import Foundation
import Testing
@testable import AVECore
@testable import AVEKit

@Suite("ChatTranscript")
struct ChatTranscriptTests {
    @Test("réponse construite phrase par phrase via reply_text")
    func sentenceBySentence() {
        var t = ChatTranscript()
        t.apply(.transcript(text: "bonjour", lang: "fra", confidence: 1))
        t.apply(.replyText(text: "Bonjour !"))
        t.apply(.replyText(text: "Comment puis-je aider ?"))
        t.apply(.ttsEnd(utteranceID: 1, interrupted: false))
        #expect(t.messages.count == 2)
        #expect(t.messages[0].role == .user && t.messages[0].text == "bonjour")
        #expect(t.messages[1].text == "Bonjour ! Comment puis-je aider ?")
        #expect(t.messages[1].status == .complete && !t.messages[1].isVoiceOnly)
    }

    @Test("sans reply_text : bulle « réponse vocale », puis texte si reply_text arrive")
    func voiceOnly() {
        var t = ChatTranscript()
        t.apply(.ttsStart(utteranceID: 1, sampleRate: 16000, latencyMs: 0))
        #expect(t.messages.last?.isVoiceOnly == true)
        t.apply(.replyText(text: "Voici."))
        #expect(t.messages.count == 1 && t.messages[0].text == "Voici." && !t.messages[0].isVoiceOnly)
    }

    @Test("interruption : la bulle est marquée interrompue")
    func interrupted() {
        var t = ChatTranscript()
        t.apply(.replyText(text: "Je commence"))
        t.apply(.ttsEnd(utteranceID: 1, interrupted: true))
        #expect(t.messages[0].status == .interrupted)
        #expect(t.currentAssistantID == nil)
    }

    @Test("turn_error : message système honnête")
    func turnError() {
        var t = ChatTranscript()
        t.apply(.turnError(code: "language_unavailable", message: nil))
        #expect(t.messages.last?.role == .system)
        #expect(t.messages.last?.text.contains("moteur vocal") == true)
    }

    @Test("carte d'action : confirmation exigée par défaut et pour confirm=true")
    func cardNeedsConfirmation() {
        var t = ChatTranscript()
        #expect(t.apply(.toolCall(name: "order_ride", args: ["utterance": .string("x")])) == nil)
        #expect(t.apply(.toolCall(name: "pay", args: ["confirm": .bool(true)])) == nil)
        #expect(t.messages.allSatisfy { $0.card?.status == .awaitingConfirmation })
    }

    @Test("confirm=false : exécution immédiate")
    func cardAuto() {
        var t = ChatTranscript()
        let auto = t.apply(.toolCall(name: "show_map", args: ["confirm": .bool(false)]))
        #expect(auto?.card?.name == "show_map" && auto?.card?.status == .confirmed)
    }

    @Test("confirmer renvoie la carte une seule fois ; refuser ne renvoie rien")
    func resolve() {
        var t = ChatTranscript()
        t.apply(.toolCall(name: "a", args: [:]))
        t.apply(.toolCall(name: "b", args: [:]))
        #expect(t.resolveCard(messageID: 1, confirmed: true)?.name == "a")
        #expect(t.resolveCard(messageID: 1, confirmed: true) == nil)
        #expect(t.resolveCard(messageID: 2, confirmed: false) == nil)
        #expect(t.message(2)?.card?.status == .declined)
    }

    @Test("résumé de carte sans le champ technique confirm")
    func summary() {
        let c = ActionCard(name: "n", args: ["confirm": .bool(true), "to": .string("Kaloum")], status: .awaitingConfirmation)
        #expect(c.summary == "to : Kaloum")
    }
}

@Suite("Orbe, langues, textes")
struct PresentationTests {
    @Test("l'état de l'orbe suit la phase quand la connexion est ouverte")
    func orbPhases() {
        let open = ConnectionState.open(resumed: false)
        #expect(OrbState(phase: .speaking, connection: open) == .speaking)
        #expect(OrbState(phase: .interrupted, connection: open) == .interrupted)
        #expect(OrbState(phase: .listening, connection: open) == .listening)
    }

    @Test("connexion non ouverte : reconnexion ou indisponible, quelle que soit la phase")
    func orbConnection() {
        #expect(OrbState(phase: .speaking, connection: .reconnecting(attempt: 1)) == .reconnecting)
        #expect(OrbState(phase: .idle, connection: .failed(.unauthorized)) == .unavailable)
        #expect(OrbState(phase: .idle, connection: .closed) == .unavailable)
    }

    @Test("accessibilité : tous les états ont libellé, aide et symbole distincts")
    func orbAccessibility() {
        let all: [OrbState] = [.idle, .listening, .thinking, .speaking, .interrupted, .reconnecting, .unavailable]
        #expect(Set(all.map(\.label)).count == all.count)
        #expect(Set(all.map(\.symbolName)).count == all.count)
        #expect(all.allSatisfy { !$0.hint.isEmpty })
        #expect(all.filter(\.isInteractive) == [.speaking])
    }

    @Test("langues : seul le français (et la détection) est annoncé disponible")
    func languages() {
        let available = LanguageCatalog.builtIn.filter(\.isAvailable).map(\.language)
        #expect(Set(available) == [.french, .auto])
        for lang in [AVELanguage.soussou, .peul, .malinke] {
            let o = LanguageCatalog.option(for: lang)
            #expect(o?.status == .unavailable)
            #expect(o?.detail.contains("Pas encore disponible") == true)
        }
        #expect(LanguageCatalog.builtIn.count == AVELanguage.allCases.count)
    }

    @Test("aucun texte ne promet une latence")
    func noLatencyPromise() {
        let texts = [UserMessages.noResponse, UserMessages.sessionRestarted, UserMessages.responseTruncated,
                     UserMessages.textInputUnavailable, UserMessages.turnError(code: "x")]
            + LanguageCatalog.builtIn.map(\.detail)
        #expect(texts.allSatisfy { !$0.contains("800") && !$0.lowercased().contains("instantan") })
    }

    @Test("erreurs fatales : un message par cas")
    func fatalMessages() {
        for e in [AVEFatalError.unauthorized, .tooManySessions, .badVersion, .unsupportedCodec, .badLang, .badSampleRate] {
            #expect(!UserMessages.fatal(e).isEmpty)
        }
    }

    @Test("coupure manuelle pendant la parole : purge + interrupt, retour au repos")
    func manualInterrupt() {
        var m = BargeInStateMachine()
        _ = m.handle(.ttsStarted)
        #expect(m.handle(.manualInterrupt) == [.purgePlayback, .sendInterrupt])
        #expect(m.phase == .idle)
        #expect(m.handle(.manualInterrupt).isEmpty)           // sans effet au repos
        #expect(m.handle(.ttsEnded(interrupted: true)).isEmpty) // reliquat ignoré
    }
}
