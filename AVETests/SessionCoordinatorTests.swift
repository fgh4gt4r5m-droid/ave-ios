import Foundation
import Testing
@testable import AVECore
@testable import AVEKit

final class FakeMic: MicSource, @unchecked Sendable {
    let frames: AsyncStream<MicFrame>
    private let cont: AsyncStream<MicFrame>.Continuation
    private let lock = NSLock()
    private var _starts = 0, _stops = 0
    init() { (frames, cont) = AsyncStream<MicFrame>.makeStream() }
    func start() { lock.withLock { _starts += 1 } }
    func stop() { lock.withLock { _stops += 1 } }
    var starts: Int { lock.withLock { _starts } }
    var stops: Int { lock.withLock { _stops } }
    func push(rms: Float) { cont.yield(MicFrame(pcm: Data(count: 640), rms: rms)) }
}

final class FakePlayer: SpeechPlayer, @unchecked Sendable {
    let levels: AsyncStream<Float>
    private let lock = NSLock()
    private var _enqueued: [Data] = []
    private var _ends = 0, _purges = 0
    init() { (levels, _) = AsyncStream<Float>.makeStream() }
    var isDrained: Bool { true }
    func enqueue(_ pcm: Data) { lock.withLock { _enqueued.append(pcm) } }
    func endOfUtterance() { lock.withLock { _ends += 1 } }
    func purge() { lock.withLock { _purges += 1 } }
    var enqueued: [Data] { lock.withLock { _enqueued } }
    var ends: Int { lock.withLock { _ends } }
    var purges: Int { lock.withLock { _purges } }
}

final class FakeLifecycle: AudioLifecycle, @unchecked Sendable {
    let events: AsyncStream<AudioSessionEvent>
    let permission: Bool
    init(permission: Bool = true) {
        self.permission = permission
        (events, _) = AsyncStream<AudioSessionEvent>.makeStream()
    }
    func requestMicrophonePermission() async -> Bool { permission }
    func activate() throws {}
    func deactivate() {}
}

@MainActor
final class FakeActivity: SessionActivityPresenting {
    private(set) var calls: [String] = []
    func start() { calls.append("start") }
    func update(_ phase: LiveActivityPhase) { calls.append("update:\(phase.rawValue)") }
    func end() { calls.append("end") }
}

final class ActionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _names: [String] = []
    func add(_ n: String) { lock.withLock { _names.append(n) } }
    var names: [String] { lock.withLock { _names } }
}

@MainActor
struct Harness {
    struct Bad: Error {}
    let coordinator: SessionCoordinator
    let factory = FakeTransportFactory()
    let mic = FakeMic()
    let player = FakePlayer()
    let actions = ActionBox()

    let preferences: InMemoryLearningPreferences

    init(permission: Bool = true, turnTimeout: Duration = .seconds(30), activity: (any SessionActivityPresenting)? = nil,
         language: AVELanguage = .french, preferences: InMemoryLearningPreferences = InMemoryLearningPreferences(),
         notices: [LearningNoticeText] = LearningNotice.all, media: MediaServices? = nil,
         configure: (inout SessionCoordinator.Configuration) -> Void = { _ in }) throws {
        self.preferences = preferences
        guard let url = URL(string: "wss://ave.test/v1/stream") else { throw Bad() }
        let client = AVEWebSocketClient(
            configuration: .init(endpoint: try AVEEndpoint(url), lang: .french,
                                 backoff: Backoff(initial: .milliseconds(5), maximum: .milliseconds(20)),
                                 pingInterval: .seconds(3600), deadPeerTimeout: nil),
            transportFactory: factory.factory)
        var config = SessionCoordinator.Configuration()
        config.vad.minSpeechFrames = 2
        config.vad.endSilenceFrames = 3
        config.vad.absoluteThreshold = 500
        config.preRollFrames = 3
        config.turnTimeout = turnTimeout
        config.learningNotices = notices
        configure(&config)
        coordinator = SessionCoordinator(
            client: client,
            devices: AudioDevices(mic: mic, player: player, lifecycle: FakeLifecycle(permission: permission)),
            configuration: config, activity: activity, language: language, learningPreferences: preferences,
            media: media)
        let box = actions
        coordinator.onAction = { card in box.add(card.name) }
    }

    /// Démarre la session et ouvre la connexion côté « serveur ».
    func open(resumed: Bool = false, learning: String? = nil) async throws -> FakeWebSocketTransport {
        await coordinator.start()
        let t = try #require(await factory.waitForTransport(0))
        t.serverReady(resumed: resumed, learning: learning)
        #expect(await eventually { await coordinator.connection == .open(resumed: resumed) })
        return t
    }

    /// L'utilisateur dit une phrase : silence, parole, silence.
    func speakOneUtterance() async {
        for _ in 0..<3 { mic.push(rms: 50) }
        for _ in 0..<2 { mic.push(rms: 2000) }
        _ = await eventually { await coordinator.phase == .listening }
        for _ in 0..<3 { mic.push(rms: 50) }
        _ = await eventually { await coordinator.phase == .thinking }
    }
}

let learningOffer = #"{"available":true,"enabled":false,"notice_version":"2026-10-v1"}"#
let learningOn = #"{"available":true,"enabled":true,"notice_version":"2026-10-v1"}"#

@MainActor
extension Harness {
    /// Un tour complet côté serveur (sans audio) : écho, une phrase, fin de tour.
    func completeTurn(_ t: FakeWebSocketTransport, utterance: Int = 5, seq: Int = 1) async {
        t.serverSend(#"{"type":"transcript","seq":\#(seq),"text":"salut","lang":"fra","confidence":1,"speculative":false,"source":"text"}"#)
        t.serverSend(#"{"type":"reply_text","seq":\#(seq + 1),"utterance_id":\#(utterance),"text":"Bonjour.","lang":"fra"}"#)
        t.serverSend(#"{"type":"turn_end","seq":\#(seq + 2),"utterance_id":\#(utterance),"interrupted":false}"#)
        _ = await eventually { await coordinator.transcript.messages.count >= 2 }
        await settle(60)
    }
}

@MainActor
@Suite("SessionCoordinator")
struct SessionCoordinatorTests {
    @Test("tour vocal complet : écoute, end_of_speech, transcription, parole, repos, cache audio, réécoute")
    func fullVoiceTurn() async throws {
        let h = try Harness()
        let t = try await h.open()
        await h.speakOneUtterance()

        #expect(await eventually { t.sentJSON.contains { $0["type"] as? String == "end_of_speech" } })
        // 3 trames de pré-roll + la trame de détection + 2 trames de parole… + la dernière : 7, dans l'ordre.
        #expect(t.sentMicSeqs == Array(1...7))

        t.serverSend(#"{"type":"transcript","seq":1,"text":"bonjour","lang":"fra","confidence":1}"#)
        t.serverSend(#"{"type":"tts_start","seq":2,"utterance_id":2,"latency_ms":0,"sample_rate":16000}"#)
        #expect(await eventually { await h.coordinator.phase == .speaking })
        t.serverSend(audio: 3, Data([1, 2]))
        t.serverSend(#"{"type":"tts_end","seq":4,"utterance_id":2,"interrupted":false}"#)
        #expect(await eventually { await h.coordinator.phase == .idle })

        #expect(h.player.enqueued == [Data([1, 2])])
        #expect(h.player.ends == 1)
        let messages = h.coordinator.transcript.messages
        #expect(messages.count == 2 && messages[0].text == "bonjour" && messages[1].isVoiceOnly)

        let assistantID = messages[1].id
        #expect(h.coordinator.hasCachedAudio(for: assistantID))
        h.coordinator.replay(messageID: assistantID)
        #expect(h.player.enqueued.count == 2 && h.player.ends == 2)
        await h.coordinator.stop()
    }

    @Test("barge-in : purge locale immédiate, interrupt envoyé, audio tardif ignoré")
    func bargeIn() async throws {
        let h = try Harness()
        let t = try await h.open()
        t.serverSend(#"{"type":"tts_start","seq":1,"utterance_id":1,"latency_ms":0,"sample_rate":16000}"#)
        #expect(await eventually { await h.coordinator.phase == .speaking })
        t.serverSend(audio: 2, Data([9, 9]))
        #expect(await eventually { h.player.enqueued.count == 1 })

        for _ in 0..<2 { h.mic.push(rms: 3000) }  // plus fort que le seuil doublé pendant la parole (1000)
        #expect(await eventually { await h.coordinator.phase == .interrupted })
        #expect(h.player.purges >= 1)
        #expect(await eventually { t.sentJSON.contains { $0["type"] as? String == "interrupt" } })

        t.serverSend(audio: 3, Data([7, 7]))  // reliquat de l'énoncé annulé
        t.serverSend(#"{"type":"tts_end","seq":4,"utterance_id":1,"interrupted":true}"#)
        #expect(await eventually { await h.coordinator.phase == .listening })
        #expect(h.player.enqueued.count == 1)
        #expect(h.coordinator.transcript.messages.last?.status == .interrupted)
        await h.coordinator.stop()
    }

    @Test("lire à voix haute : speak au moteur, aucune nouvelle bulle, audio gardé ensuite")
    func readAloud() async throws {
        let h = try Harness()
        let t = try await h.open()
        await h.completeTurn(t)  // réponse écrite « Bonjour. », sans audio
        let assistant = try #require(h.coordinator.transcript.messages.last)
        #expect(assistant.role == .assistant && !h.coordinator.hasCachedAudio(for: assistant.id))
        #expect(h.coordinator.canReadAloud(messageID: assistant.id))

        await h.coordinator.readAloud(messageID: assistant.id)
        #expect(await eventually { t.sentJSON.contains { $0["type"] as? String == "speak" && $0["text"] as? String == "Bonjour." } })
        #expect(h.coordinator.replayingMessageID == assistant.id)

        t.serverSend(#"{"type":"tts_start","seq":4,"utterance_id":6,"latency_ms":0,"sample_rate":16000}"#)
        t.serverSend(audio: 5, Data([4, 2]))
        t.serverSend(#"{"type":"tts_end","seq":6,"utterance_id":6,"interrupted":false}"#)
        t.serverSend(#"{"type":"turn_end","seq":7,"utterance_id":6,"interrupted":false}"#)
        #expect(await eventually { await h.coordinator.hasCachedAudio(for: assistant.id) })
        #expect(h.coordinator.transcript.messages.count == 2)      // pas de bulle « Réponse vocale » en plus
        #expect(h.player.enqueued == [Data([4, 2])])
        #expect(await eventually { await h.coordinator.replayingMessageID == nil })
        await h.coordinator.stop()
    }

    @Test("lire à voix haute : impossible pour une réponse trop longue pour speak ou une carte d'action")
    func readAloudLimits() async throws {
        let h = try Harness()
        let t = try await h.open()
        let long = String(repeating: "a", count: SessionCoordinator.speakMaxCharacters + 1)
        t.serverSend(#"{"type":"transcript","seq":1,"text":"x","lang":"fra","confidence":1,"speculative":false,"source":"text"}"#)
        t.serverSend(#"{"type":"reply_text","seq":2,"utterance_id":5,"text":"\#(long)","lang":"fra"}"#)
        t.serverSend(#"{"type":"turn_end","seq":3,"utterance_id":5,"interrupted":false}"#)
        #expect(await eventually { await h.coordinator.transcript.messages.count >= 2 })
        let assistant = try #require(h.coordinator.transcript.messages.last)
        #expect(!h.coordinator.canReadAloud(messageID: assistant.id))
        await h.coordinator.readAloud(messageID: assistant.id)
        #expect(!t.sentJSON.contains { $0["type"] as? String == "speak" })
        await h.coordinator.stop()
    }

    @Test("turn_error language_unavailable : message honnête, retour au repos")
    func languageUnavailable() async throws {
        let h = try Harness()
        let t = try await h.open()
        await h.speakOneUtterance()
        t.serverSend(#"{"type":"turn_error","seq":1,"code":"language_unavailable","message":"m","lang":"sus"}"#)
        #expect(await eventually { await h.coordinator.phase == .idle })
        #expect(h.coordinator.transcript.messages.last?.text.contains("disponible à la voix") == true)
        await h.coordinator.stop()
    }

    @Test("pas de réponse : le tour est abandonné après le délai")
    func turnTimeout() async throws {
        let h = try Harness(turnTimeout: .milliseconds(150))
        _ = try await h.open()
        await h.speakOneUtterance()
        #expect(await eventually { await h.coordinator.phase == .idle })
        #expect(h.coordinator.transcript.messages.last?.text == UserMessages.noResponse)
        await h.coordinator.stop()
    }

    @Test("voix → texte → voix sans rompre la session")
    func modeSwitchKeepsSession() async throws {
        let h = try Harness()
        _ = try await h.open()
        #expect(h.mic.starts == 1)
        await h.coordinator.setMode(.text)
        #expect(h.mic.stops == 1 && h.coordinator.mode == .text)
        #expect(h.coordinator.connection == .open(resumed: false))
        await h.coordinator.setMode(.voice)
        #expect(h.mic.starts == 2)
        await settle()
        #expect(h.factory.count == 1)  // aucune nouvelle connexion
        await h.coordinator.stop()
    }

    @Test("micro refusé : bascule en mode texte avec explication")
    func microphoneDenied() async throws {
        let h = try Harness(permission: false)
        await h.coordinator.start()
        #expect(h.coordinator.mode == .text)
        #expect(h.coordinator.notice == UserMessages.microphoneDenied)
        #expect(h.mic.starts == 0)
        await h.coordinator.stop()
    }

    @Test("texte : envoyé tel quel, bulle utilisateur à l'écho serveur, réponse par reply_text, tour clos par turn_end")
    func textTurn() async throws {
        let h = try Harness()
        let t = try await h.open()
        await h.coordinator.setMode(.text)
        await h.coordinator.sendText("  Où est ma course ?  ")
        #expect(await eventually { t.sentJSON.contains { $0["type"] as? String == "text" } })
        #expect(t.sentJSON.last?["text"] as? String == "Où est ma course ?")
        #expect(h.coordinator.phase == .thinking)
        #expect(h.coordinator.transcript.messages.isEmpty)  // pas de bulle locale : on attend l'écho

        t.serverSend(#"{"type":"transcript","seq":1,"text":"Où est ma course ?","lang":"fra","confidence":1,"speculative":false,"source":"text"}"#)
        t.serverSend(#"{"type":"reply_text","seq":2,"utterance_id":2,"text":"Elle arrive.","lang":"fra"}"#)
        t.serverSend(#"{"type":"turn_end","seq":3,"utterance_id":2,"interrupted":false}"#)
        #expect(await eventually { await h.coordinator.phase == .idle })
        let messages = h.coordinator.transcript.messages
        #expect(messages.map(\.text) == ["Où est ma course ?", "Elle arrive."])
        #expect(messages[1].status == .complete)
        await h.coordinator.stop()
    }

    @Test("texte envoyé pendant que l'assistant parle : purge locale, pas d'interrupt (le serveur coupe seul)")
    func textBargeIn() async throws {
        let h = try Harness()
        let t = try await h.open()
        t.serverSend(#"{"type":"tts_start","seq":1,"utterance_id":1,"latency_ms":0,"sample_rate":16000}"#)
        #expect(await eventually { await h.coordinator.phase == .speaking })
        await h.coordinator.sendText("stop")
        #expect(h.player.purges >= 1)
        // Suite @MainActor : `phase` se lit sans `await` (le compilateur le signalait comme inutile).
        #expect(h.coordinator.phase == .thinking)
        #expect(!t.sentJSON.contains { $0["type"] as? String == "interrupt" })
        await h.coordinator.stop()
    }

    @Test("texte hors ligne : message gardé « en attente », envoyé dans l'ordre au retour du réseau")
    func textOffline() async throws {
        let h = try Harness()  // pas encore démarré : pas de session prête
        await h.coordinator.sendText("salut")
        await h.coordinator.sendText("ça va ?")
        #expect(h.coordinator.pendingTexts.map(\.text) == ["salut", "ça va ?"])
        #expect(h.coordinator.notice == nil)
        let t = try await h.open()
        #expect(await eventually { await h.coordinator.pendingTexts.isEmpty })
        let sent = t.sentJSON.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
        #expect(sent == ["salut", "ça va ?"])
        let tooLong = String(repeating: "a", count: 4001)
        await h.coordinator.sendText(tooLong)
        #expect(h.coordinator.notice == UserMessages.textTooLong)
    }

    @Test("langues du serveur : la liste affichée suit ready.languages")
    func serverLanguagesShown() async throws {
        let h = try Harness()
        await h.coordinator.start()
        let t = try #require(await h.factory.waitForTransport(0))
        t.serverReady(languages: #"[{"code":"fra","name":"Français","native":"Français","regions":[],"status":"production","available":true},{"code":"sus","name":"Soussou","native":"Sosoxui","regions":[],"status":"planned","available":false}]"#)
        #expect(await eventually { await h.coordinator.languageOptions.count == 3 })  // fra, sus + détection
        await h.coordinator.stop()
    }

    @Test("actions : rien ne part sans confirmation quand confirm=true")
    func actionConfirmation() async throws {
        let h = try Harness()
        let t = try await h.open()
        t.serverSend(#"{"type":"action","seq":1,"name":"cancel_ride","args":{"ride":"r1"},"confirm":true}"#)
        t.serverSend(#"{"type":"action","seq":2,"name":"transfer","args":{},"confirm":true}"#)
        t.serverSend(#"{"type":"action","seq":3,"name":"show_map","args":{},"confirm":false}"#)
        #expect(await eventually { await h.coordinator.transcript.messages.count == 3 })
        #expect(h.actions.names == ["show_map"])
        let msgs = h.coordinator.transcript.messages
        h.coordinator.confirmAction(messageID: msgs[0].id)
        h.coordinator.declineAction(messageID: msgs[1].id)
        #expect(h.actions.names == ["show_map", "cancel_ride"])
        await h.coordinator.stop()
    }

    @Test("session expirée : l'utilisateur est prévenu que la conversation repart de zéro")
    func sessionRestarted() async throws {
        let h = try Harness()
        let t0 = try await h.open()
        t0.serverDrop()
        let t1 = try #require(await h.factory.waitForTransport(1))
        t1.serverReady(session: "autre", resumed: false)
        #expect(await eventually { await h.coordinator.notice == UserMessages.sessionRestarted })
        await h.coordinator.stop()
    }

    @Test("Live Activity : démarrée à l'ouverture, seulement les changements d'état, terminée à l'arrêt")
    func liveActivityLifecycle() async throws {
        let fake = FakeActivity()
        let h = try Harness(activity: fake)
        await h.coordinator.start()
        #expect(fake.calls.isEmpty)  // rien tant que la session n'est pas ouverte
        let t = try #require(await h.factory.waitForTransport(0))
        t.serverReady()
        #expect(await eventually { await fake.calls.count >= 2 })
        #expect(fake.calls.prefix(2) == ["start", "update:idle"])
        await h.speakOneUtterance()
        #expect(fake.calls.contains("update:listening") && fake.calls.contains("update:thinking"))
        zip(fake.calls, fake.calls.dropFirst()).forEach { #expect($0 != $1) }  // aucune mise à jour redondante
        #expect(fake.calls.filter { $0 == "start" }.count == 1)
        await h.coordinator.stop()
        #expect(fake.calls.last == "end" && fake.calls.filter { $0 == "end" }.count == 1)
    }

    @Test("Live Activity : jamais démarrée si la session échoue d'emblée, aucun état ne fuite")
    func liveActivityNeverStartedOnFatal() async throws {
        let fake = FakeActivity()
        let h = try Harness(activity: fake)
        await h.coordinator.start()
        let t = try #require(await h.factory.waitForTransport(0))
        t.serverSend(#"{"type":"error","code":"unauthorized","message":"m"}"#)
        t.serverDrop()
        #expect(await eventually { await h.coordinator.orbState == .unavailable })
        #expect(fake.calls.isEmpty)
        await h.coordinator.stop()
    }

    @Test("erreur fatale : message clair, état indisponible")
    func fatalError() async throws {
        let h = try Harness()
        await h.coordinator.start()
        let t = try #require(await h.factory.waitForTransport(0))
        t.serverSend(#"{"type":"error","code":"unauthorized","message":"m"}"#)
        t.serverDrop()
        #expect(await eventually { await h.coordinator.orbState == .unavailable })
        #expect(h.coordinator.notice == UserMessages.fatal(.unauthorized))
        await h.coordinator.stop()
    }
}

@MainActor
@Suite("Apprentissage et consentement")
struct LearningCoordinatorTests {
    private let v2 = LearningNoticeText(version: "2026-11-v2", languages: [.french], speechLanguageCode: "fr-FR",
                                        title: "t", body: "b", yes: "o", no: "n")

    @Test("la demande n'apparaît qu'après le premier tour terminé ; la réponse part avec la version AFFICHÉE")
    func promptAfterFirstTurn() async throws {
        let h = try Harness()
        let t = try await h.open(learning: learningOffer)
        await settle(60)
        #expect(h.coordinator.learningPrompt == nil)  // pas avant d'avoir vu l'app fonctionner
        await h.completeTurn(t)
        #expect(await eventually { await h.coordinator.learningPrompt?.version == "2026-10-v1" })

        await h.coordinator.answerLearning(granted: true)
        #expect(h.coordinator.learningPrompt == nil)
        #expect(await eventually { t.sentJSON.contains { $0["type"] as? String == "learning_consent" } })
        let sent = try #require(t.sentJSON.last { $0["type"] as? String == "learning_consent" })
        #expect(sent["granted"] as? Bool == true && sent["version"] as? String == "2026-10-v1")

        t.serverSend(#"{"type":"learning_state","enabled":true,"reason":"granted"}"#)
        #expect(await eventually { await h.coordinator.learning?.enabled == true })
        #expect(h.coordinator.learningMessage == UserMessages.learningThanks)
        await h.coordinator.stop()
    }

    @Test("un refus est envoyé, mémorisé, et la même version n'est plus jamais redemandée")
    func declineIsRemembered() async throws {
        let prefs = InMemoryLearningPreferences()
        let h = try Harness(preferences: prefs)
        let t = try await h.open(learning: learningOffer)
        await h.completeTurn(t)
        #expect(await eventually { await h.coordinator.learningPrompt != nil })
        await h.coordinator.answerLearning(granted: false)
        #expect(prefs.declinedVersion == "2026-10-v1")
        #expect(await eventually { t.sentJSON.contains { $0["type"] as? String == "learning_consent" && $0["granted"] as? Bool == false } })
        await h.coordinator.stop()

        let h2 = try Harness(preferences: prefs)  // nouvelle session, même appareil
        let t2 = try await h2.open(learning: learningOffer)
        await h2.completeTurn(t2)
        await h2.completeTurn(t2, utterance: 6, seq: 10)
        #expect(h2.coordinator.learningPrompt == nil)
        await h2.coordinator.stop()
    }

    @Test("rien n'est demandé si non disponible, déjà accepté, version inconnue ou langue sans notice")
    func noPrompt() async throws {
        let cases: [(String, AVELanguage)] = [
            (#"{"available":false,"enabled":false,"notice_version":"2026-10-v1"}"#, .french),
            (learningOn, .french),
            (#"{"available":true,"enabled":false,"notice_version":"2099-01-v9"}"#, .french),
            (learningOffer, .soussou),
        ]
        for (learning, language) in cases {
            let h = try Harness(language: language)
            let t = try await h.open(learning: learning)
            await h.completeTurn(t)
            #expect(h.coordinator.learningPrompt == nil, "\(learning) / \(language)")
            await h.coordinator.stop()
        }
    }

    @Test("invité : jamais sollicité (l'effacement promis par la notice ne pourrait pas être tenu), même option masquée dans les réglages")
    func guestNeverAsked() async throws {
        let h = try Harness()
        h.coordinator.accountKind = .guest
        let t = try await h.open(learning: learningOffer)
        await h.completeTurn(t)
        await h.completeTurn(t, utterance: 6, seq: 10)
        #expect(h.coordinator.learningPrompt == nil && !h.coordinator.learningOfferedToUser)
        h.coordinator.presentLearningPrompt()  // même à la demande explicite
        #expect(h.coordinator.learningPrompt == nil)
        // Un invité qui crée un compte peut ensuite être sollicité.
        h.coordinator.accountKind = .phone
        #expect(h.coordinator.learningOfferedToUser)
        h.coordinator.presentLearningPrompt()
        #expect(h.coordinator.learningPrompt?.version == "2026-10-v1")
        await h.coordinator.stop()
    }

    @Test("serveur ancien (pas de ready.learning) : jamais de demande")
    func legacyServer() async throws {
        let h = try Harness()
        let t = try await h.open()
        await h.completeTurn(t)
        #expect(h.coordinator.learning == nil && h.coordinator.learningPrompt == nil)
        await h.coordinator.stop()
    }

    @Test("pas de relance dans la même session après fermeture sans réponse ; rien n'est envoyé")
    func askedOnce() async throws {
        let h = try Harness()
        let t = try await h.open(learning: learningOffer)
        await h.completeTurn(t)
        #expect(await eventually { await h.coordinator.learningPrompt != nil })
        h.coordinator.dismissLearningPrompt()
        await h.completeTurn(t, utterance: 6, seq: 10)
        #expect(h.coordinator.learningPrompt == nil)
        #expect(!t.sentJSON.contains { $0["type"] as? String == "learning_consent" })
        await h.coordinator.stop()
    }

    @Test("le micro est ignoré tant que la notice est affichée")
    func micIgnoredWhilePrompt() async throws {
        let h = try Harness()
        let t = try await h.open(learning: learningOffer)
        await h.completeTurn(t)
        #expect(await eventually { await h.coordinator.learningPrompt != nil })
        for _ in 0..<6 { h.mic.push(rms: 3000) }
        await settle(150)
        #expect(t.sentMicSeqs.isEmpty && h.coordinator.phase == .idle)
        await h.coordinator.stop()
    }

    @Test("réponse hors ligne : la notice reste affichée, rien n'est perdu en silence")
    func offlineAnswer() async throws {
        let h = try Harness()
        let t = try await h.open(learning: learningOffer)
        await h.completeTurn(t)
        #expect(await eventually { await h.coordinator.learningPrompt != nil })
        t.serverDrop()
        #expect(await eventually { await h.coordinator.connection != .open(resumed: false) })
        await h.coordinator.answerLearning(granted: true)
        #expect(h.coordinator.learningPrompt != nil && h.coordinator.notice == UserMessages.notConnected)
        #expect(h.preferences.declinedVersion == nil)
        await h.coordinator.stop()
    }

    @Test("notice périmée : nouvelle demande seulement si on possède le texte exact de la nouvelle version")
    func staleNotice() async throws {
        let h = try Harness(notices: LearningNotice.all + [v2])
        let t = try await h.open(learning: learningOffer)
        await h.completeTurn(t)
        #expect(await eventually { await h.coordinator.learningPrompt != nil })
        await h.coordinator.answerLearning(granted: true)
        t.serverSend(#"{"type":"learning_state","enabled":false,"reason":"stale_notice","notice_version":"2026-11-v2"}"#)
        #expect(await eventually { await h.coordinator.learningPrompt?.version == "2026-11-v2" })
        await h.coordinator.stop()
    }

    @Test("retirer son aide : demande envoyée, éléments effacés annoncés, version non redemandée")
    func revoke() async throws {
        let h = try Harness()
        let t = try await h.open(learning: learningOn)
        await h.coordinator.revokeLearning()
        #expect(await eventually { t.sentJSON.contains { $0["type"] as? String == "learning_revoke" } })
        t.serverSend(#"{"type":"learning_state","enabled":false,"reason":"revoked","deleted":3}"#)
        #expect(await eventually { await h.coordinator.learning?.enabled == false })
        #expect(h.coordinator.learningMessage?.contains("3 éléments effacés") == true)
        #expect(h.preferences.declinedVersion == "2026-10-v1")
        await h.coordinator.stop()
    }

    @Test("👍/👎 : seulement avec consentement, une fois par message, borné à 1000 caractères")
    func feedback() async throws {
        let h = try Harness()
        let t = try await h.open(learning: learningOn)
        await h.completeTurn(t, utterance: 5)
        let message = try #require(h.coordinator.transcript.messages.last)
        await h.coordinator.sendFeedback(messageID: message.id, rating: .up)
        await h.coordinator.sendFeedback(messageID: message.id, rating: .down)  // déjà noté
        #expect(await eventually { t.sentJSON.contains { $0["type"] as? String == "feedback" } })
        let sent = t.sentJSON.filter { $0["type"] as? String == "feedback" }
        #expect(sent.count == 1 && sent[0]["utterance_id"] as? Int == 5 && sent[0]["rating"] as? String == "up")
        #expect(h.coordinator.feedbackGiven.contains(message.id))

        t.serverSend(#"{"type":"feedback_ack","stored":true}"#)
        #expect(await eventually { await h.coordinator.learningMessage == UserMessages.feedbackThanks })
        await h.coordinator.stop()
    }

    @Test("👍/👎 sans consentement ou correction trop longue : rien n'est envoyé")
    func feedbackRefused() async throws {
        let off = try Harness()
        let t0 = try await off.open(learning: learningOffer)
        await off.completeTurn(t0)
        let m0 = try #require(off.coordinator.transcript.messages.last)
        await off.coordinator.sendFeedback(messageID: m0.id, rating: .up)
        #expect(!t0.sentJSON.contains { $0["type"] as? String == "feedback" })
        await off.coordinator.stop()

        let on = try Harness()
        let t1 = try await on.open(learning: learningOn)
        await on.completeTurn(t1)
        let m1 = try #require(on.coordinator.transcript.messages.last)
        await on.coordinator.sendFeedback(messageID: m1.id, rating: .down, correction: String(repeating: "a", count: 1001))
        #expect(on.coordinator.notice == UserMessages.feedbackTooLong)
        #expect(!t1.sentJSON.contains { $0["type"] as? String == "feedback" })
        await on.coordinator.stop()
    }
}
