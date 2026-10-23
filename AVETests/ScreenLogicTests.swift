import Foundation
import Testing
@testable import AVECore
@testable import AVEKit

@Suite("ChatTranscript")
struct ChatTranscriptTests {
    private func transcript(_ text: String, source: ServerEvent.TranscriptSource = .voice, speculative: Bool = false) -> ServerEvent {
        .transcript(text: text, lang: "fra", confidence: 1, speculative: speculative, source: source)
    }

    @Test("réponse construite phrase par phrase via reply_text, par utterance_id")
    func sentenceBySentence() {
        var t = ChatTranscript()
        t.apply(transcript("bonjour"))
        t.apply(.replyText(utteranceID: 2, text: "Bonjour !", lang: "fra"))
        // Texte exact (D7) : le séparateur fait partie de la phrase suivante ; l'app n'ajoute rien.
        t.apply(.replyText(utteranceID: 2, text: " Comment puis-je aider ?", lang: "fra"))
        t.apply(.turnEnd(utteranceID: 2, interrupted: false))
        #expect(t.messages.count == 2)
        #expect(t.messages[0].role == .user && t.messages[0].text == "bonjour")
        #expect(t.messages[1].text == "Bonjour ! Comment puis-je aider ?")
        #expect(t.messages[1].status == .complete && !t.messages[1].isVoiceOnly)
    }

    @Test("deux tours = deux bulles assistant distinctes")
    func twoTurns() {
        var t = ChatTranscript()
        t.apply(.replyText(utteranceID: 1, text: "Un.", lang: "fra"))
        t.apply(.turnEnd(utteranceID: 1, interrupted: false))
        t.apply(.replyText(utteranceID: 5, text: "Deux.", lang: "fra"))
        #expect(t.messages.map(\.text) == ["Un.", "Deux."])
    }

    @Test("l'écho d'un message texte crée la bulle utilisateur, comme la voix")
    func textEcho() {
        var t = ChatTranscript()
        t.apply(transcript("salut", source: .text))
        #expect(t.messages.count == 1 && t.messages[0].role == .user && t.messages[0].text == "salut")
    }

    @Test("transcript speculative:true = calculé d'avance, donc FINAL : la bulle apparaît")
    func speculativeIsFinal() {
        var t = ChatTranscript()
        t.apply(transcript("bonjour", speculative: true))
        #expect(t.messages.count == 1 && t.messages[0].text == "bonjour")
    }

    @Test("sans reply_text : bulle « réponse vocale », puis texte si reply_text arrive")
    func voiceOnly() {
        var t = ChatTranscript()
        t.apply(.ttsStart(utteranceID: 4, sampleRate: 16000, latencyMs: 0))
        #expect(t.messages.last?.isVoiceOnly == true)
        t.apply(.replyText(utteranceID: 4, text: "Voici.", lang: "fra"))
        #expect(t.messages.count == 1 && t.messages[0].text == "Voici." && !t.messages[0].isVoiceOnly)
    }

    @Test("reply_text puis tts_start du même tour : une seule bulle")
    func replyThenTTS() {
        var t = ChatTranscript()
        t.apply(.replyText(utteranceID: 3, text: "Salut.", lang: "fra"))
        t.apply(.ttsStart(utteranceID: 3, sampleRate: 16000, latencyMs: 0))
        #expect(t.messages.count == 1)
    }

    @Test("turn_end interrompu : la bulle est marquée interrompue")
    func interrupted() {
        var t = ChatTranscript()
        t.apply(.replyText(utteranceID: 1, text: "Je commence", lang: "fra"))
        t.apply(.turnEnd(utteranceID: 1, interrupted: true))
        #expect(t.messages[0].status == .interrupted)
        #expect(t.currentAssistantID == nil)
    }

    @Test("tts_end interrompu : bulle interrompue ; tts_end normal : le tour reste ouvert")
    func ttsEndInterrupted() {
        var t = ChatTranscript()
        t.apply(.replyText(utteranceID: 1, text: "Première phrase.", lang: "fra"))
        t.apply(.ttsEnd(utteranceID: 1, interrupted: false))
        #expect(t.messages[0].status == .streaming && t.currentAssistantID == t.messages[0].id)
        t.apply(.ttsEnd(utteranceID: 1, interrupted: true))
        #expect(t.messages[0].status == .interrupted)
        #expect(t.currentAssistantID == nil)
    }

    @Test("turn_error : message système honnête, rate_limited compris")
    func turnError() {
        var t = ChatTranscript()
        t.apply(.turnError(code: "language_unavailable", message: "", lang: "sus", retryAfterSeconds: nil))
        #expect(t.messages.last?.role == .system && t.messages.last?.text.contains("moteur vocal") == true)
        t.apply(.turnError(code: "rate_limited", message: "", lang: nil, retryAfterSeconds: nil))
        #expect(t.messages.last?.text.contains("trop de messages") == true)
        t.apply(.turnError(code: "rate_limited", message: "", lang: nil, retryAfterSeconds: 3))
        #expect(t.messages.last?.text.contains("3 s") == true)
        t.apply(.turnError(code: "code_inconnu", message: "", lang: nil, retryAfterSeconds: nil))
        #expect(t.messages.last?.role == .system)
    }

    @Test("action confirm=true : carte en attente, rien à exécuter")
    func cardNeedsConfirmation() {
        var t = ChatTranscript()
        #expect(t.apply(.action(name: "cancel_ride", args: ["ride": .string("r1")], confirm: true)) == nil)
        #expect(t.messages[0].card?.status == .awaitingConfirmation && t.messages[0].card?.requiresConfirmation == true)
    }

    @Test("action confirm=false : exécution immédiate")
    func cardAuto() {
        var t = ChatTranscript()
        let auto = t.apply(.action(name: "show_map", args: [:], confirm: false))
        #expect(auto?.card?.name == "show_map" && auto?.card?.status == .confirmed)
    }

    @Test("confirmer renvoie la carte une seule fois ; refuser ne renvoie rien")
    func resolve() {
        var t = ChatTranscript()
        t.apply(.action(name: "a", args: [:], confirm: true))
        t.apply(.action(name: "b", args: [:], confirm: true))
        #expect(t.resolveCard(messageID: 1, confirmed: true)?.name == "a")
        #expect(t.resolveCard(messageID: 1, confirmed: true) == nil)
        #expect(t.resolveCard(messageID: 2, confirmed: false) == nil)
        #expect(t.message(2)?.card?.status == .declined)
    }

    @Test("résumé de carte : arguments textuels, triés")
    func summary() {
        let c = ActionCard(name: "n", args: ["to": .string("Kaloum"), "n": .number(2), "a": .string("x")],
                           requiresConfirmation: true, status: .awaitingConfirmation)
        #expect(c.summary == "a : x\nto : Kaloum")
    }
}

@Suite("Live Activity et palette")
struct BrandAndActivityTests {
    @Test("la Live Activity suit l'orbe ; session perdue = arrêt (nil)")
    func phaseMapping() {
        #expect(LiveActivityPhase(orb: .listening) == .listening)
        #expect(LiveActivityPhase(orb: .speaking) == .speaking)
        #expect(LiveActivityPhase(orb: .interrupted) == .interrupted)
        #expect(LiveActivityPhase(orb: .reconnecting) == .reconnecting)
        #expect(LiveActivityPhase(orb: .unavailable) == nil)
    }

    @Test("libellés et symboles distincts ; état sérialisable (aucun texte de conversation)")
    func phaseContent() {
        let all: [LiveActivityPhase] = [.idle, .listening, .thinking, .speaking, .interrupted, .reconnecting]
        #expect(Set(all.map(\.label)).count == all.count && Set(all.map(\.symbolName)).count == all.count)
        #expect(all.allSatisfy { LiveActivityPhase(rawValue: $0.rawValue) == $0 })
    }

    @Test("conversion hexadécimale")
    func hex() {
        let c = AVEColor(hex: 0x5EA0FD)
        #expect(c.red == 0x5E && c.green == 0xA0 && c.blue == 0xFD)
    }

    @Test("contrastes WCAG des couples de la charte (texte ≥ 4,5 ; décor ≥ 3)")
    func contrasts() {
        let p = AVEPalette.self
        #expect(p.navy.contrast(with: p.blue) >= 4.5)      // texte et icônes sur l'accent
        #expect(p.white.contrast(with: p.surface) >= 4.5)  // bulles de l'assistant
        #expect(p.amber.contrast(with: p.navy) >= 4.5)     // avertissements sur le fond
        #expect(p.amber.contrast(with: p.surface) >= 4.5)
        #expect(p.blue.contrast(with: p.navy) >= 4.5)
        #expect(p.violet.contrast(with: p.navy) >= 3)      // décor seulement
        #expect(p.white.contrast(with: p.blue) < 4.5)      // piège connu : blanc sur bleu vif = insuffisant
        // Apparence claire (fond blanc) et sombre (fond noir du système).
        #expect(p.blueOnLight.contrast(with: p.white) >= 4.5)   // accent en texte sur blanc
        #expect(p.white.contrast(with: p.blueOnLight) >= 4.5)   // icône blanche sur le bouton d'accent
        #expect(p.amberOnLight.contrast(with: p.white) >= 4.5)  // avertissements sur blanc
        #expect(p.blue.contrast(with: p.black) >= 4.5 && p.amber.contrast(with: p.black) >= 4.5)
        #expect(p.navy.contrast(with: p.blue) >= 4.5)           // icône bleu nuit sur le bouton d'accent (sombre)
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
        #expect(all.allSatisfy { !$0.hint.isEmpty && !$0.caption.isEmpty })
        // La légende visible ne parle jamais du geste VoiceOver.
        #expect(all.allSatisfy { !$0.caption.contains("deux fois") })
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

    @Test("langues du serveur : disponibilité réelle, codes inconnus ignorés, détection ajoutée")
    func serverLanguages() {
        let server: [LanguageInfo] = [
            LanguageInfo(code: "fra", name: "Français", native: "Français", status: "production", available: true),
            LanguageInfo(code: "sus", name: "Soussou", native: "Sosoxui", status: "planned", available: false),
            LanguageInfo(code: "wol", name: "Wolof", native: "Wolof", status: "experimental", available: true),
            LanguageInfo(code: "zzz", name: "Inconnue", native: "?", status: "planned", available: true),
            LanguageInfo(code: "zul", name: "Zoulou", native: "isiZulu", status: "planned", available: nil),
        ]
        let options = LanguageCatalog.options(from: server)
        #expect(options.map(\.language) == [.french, .soussou, .wolof, .zulu, .auto])
        #expect(options[0].isAvailable && !options[1].isAvailable && options[2].isAvailable)
        #expect(options[2].detail.contains("expérimental"))
        #expect(!options[3].isAvailable && options[3].detail.contains("inconnue"))
        #expect(LanguageCatalog.options(from: nil) == LanguageCatalog.builtIn)
        #expect(LanguageCatalog.options(from: []) == LanguageCatalog.builtIn)
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

    @Test("texte envoyé : réflexion ; pendant la parole, purge locale sans interrupt (le serveur coupe seul)")
    func textSent() {
        var m = BargeInStateMachine()
        #expect(m.handle(.userSentText).isEmpty && m.phase == .thinking)
        _ = m.handle(.ttsStarted)
        #expect(m.handle(.userSentText) == [.purgePlayback] && m.phase == .thinking)
    }

    @Test("fin de tour sans audio : retour au repos ; le turn_end interrompu d'un tour coupé est ignoré")
    func turnEnded() {
        var m = BargeInStateMachine()
        _ = m.handle(.userSentText)
        _ = m.handle(.turnEnded(interrupted: true))
        #expect(m.phase == .thinking)  // reliquat
        _ = m.handle(.turnEnded(interrupted: false))
        #expect(m.phase == .idle)
    }
}
