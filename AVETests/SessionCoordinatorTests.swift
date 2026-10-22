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

    init(permission: Bool = true, turnTimeout: Duration = .seconds(30), activity: (any SessionActivityPresenting)? = nil) throws {
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
        coordinator = SessionCoordinator(
            client: client,
            devices: AudioDevices(mic: mic, player: player, lifecycle: FakeLifecycle(permission: permission)),
            configuration: config, activity: activity)
        let box = actions
        coordinator.onAction = { card in box.add(card.name) }
    }

    /// Démarre la session et ouvre la connexion côté « serveur ».
    func open(resumed: Bool = false) async throws -> FakeWebSocketTransport {
        await coordinator.start()
        let t = try #require(await factory.waitForTransport(0))
        t.serverReady(resumed: resumed)
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

    @Test("turn_error language_unavailable : message honnête, retour au repos")
    func languageUnavailable() async throws {
        let h = try Harness()
        let t = try await h.open()
        await h.speakOneUtterance()
        t.serverSend(#"{"type":"turn_error","seq":1,"code":"language_unavailable","message":"m","lang":"sus"}"#)
        #expect(await eventually { await h.coordinator.phase == .idle })
        #expect(h.coordinator.transcript.messages.last?.text.contains("moteur vocal") == true)
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
        #expect(await h.coordinator.phase == .thinking)
        #expect(!t.sentJSON.contains { $0["type"] as? String == "interrupt" })
        await h.coordinator.stop()
    }

    @Test("texte hors ligne : message non perdu en silence, l'utilisateur est prévenu")
    func textOffline() async throws {
        let h = try Harness()  // jamais démarré : pas de session prête
        await h.coordinator.sendText("salut")
        #expect(h.coordinator.notice == UserMessages.notConnected)
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
