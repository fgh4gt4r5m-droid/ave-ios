import Foundation
import Testing
@testable import AVECore

@Suite("AVEWebSocketClient")
struct AVEWebSocketClientTests {
    private func makeClient(
        factory: FakeTransportFactory,
        token: String? = nil,
        capacity: Int = 500,
        ping: Duration = .seconds(3600)
    ) throws -> AVEWebSocketClient {
        let url = try #require(URL(string: "wss://ave.test/v1/stream"))
        let config = AVEWebSocketClient.Configuration(
            endpoint: try AVEEndpoint(url), lang: .french,
            backoff: Backoff(initial: .milliseconds(5), maximum: .milliseconds(20)),
            pingInterval: ping, deadPeerTimeout: nil, micQueueCapacity: capacity)
        return AVEWebSocketClient(configuration: config, tokenProvider: { token },
                                  transportFactory: factory.factory)
    }

    private func pcm(_ n: Int16) -> Data { PCM16.data(from: [n]) }

    // MARK: hello / ready

    @Test("hello : jeton dans le message, jamais dans l'URL")
    func helloCarriesToken() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f, token: "secret-token")
        await client.start()
        let t = try #require(await f.waitForTransport(0))
        #expect(await eventually { !t.sentJSON.isEmpty })
        let hello = t.sentJSON[0]
        #expect(hello["type"] as? String == "hello")
        #expect(hello["token"] as? String == "secret-token")
        #expect(hello["session_id"] == nil)
        #expect(!f.urls[0].absoluteString.contains("secret-token"))
        await client.stop()
    }

    @Test("ready → état open ; la bascule d'état est émise")
    func readyOpens() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f)
        let rec = EventRecorder.record(client.events)
        await client.start()
        let t = try #require(await f.waitForTransport(0))
        t.serverReady()
        #expect(await eventually { await rec.states.contains(.open(resumed: false)) })
        #expect(await rec.states.first == .connecting)
        await client.stop()
    }

    // MARK: file micro

    @Test("rien n'est envoyé avant ready ; la file est renvoyée selon last_mic_seq")
    func micQueueResent() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f)
        await client.start()
        for i in 1...4 { await client.sendMic(pcm(Int16(i))) }
        let t = try #require(await f.waitForTransport(0))
        #expect(await eventually { !t.sentJSON.isEmpty })
        #expect(t.sentMicSeqs.isEmpty)
        t.serverReady(lastMicSeq: 2)  // le serveur a déjà reçu 1 et 2
        #expect(await eventually { t.sentMicSeqs.count == 2 })
        #expect(t.sentMicSeqs == [3, 4])
        await client.stop()
    }

    @Test("file micro bornée : les plus anciens chunks sont abandonnés")
    func micQueueBounded() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f, capacity: 3)
        await client.start()
        for i in 1...5 { await client.sendMic(pcm(Int16(i))) }
        let t = try #require(await f.waitForTransport(0))
        t.serverReady(lastMicSeq: 0)
        #expect(await eventually { t.sentMicSeqs.count == 3 })
        #expect(t.sentMicSeqs == [3, 4, 5])
        await client.stop()
    }

    @Test("en ligne, le micro part immédiatement et la numérotation continue après reconnexion")
    func micContinuesAcrossReconnect() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f)
        await client.start()
        let t0 = try #require(await f.waitForTransport(0))
        t0.serverReady()
        #expect(await eventually { await client.isReadyForTests })
        await client.sendMic(pcm(1))
        await client.sendMic(pcm(2))
        #expect(await eventually { t0.sentMicSeqs == [1, 2] })
        t0.serverDrop()
        await client.sendMic(pcm(3))  // hors ligne
        let t1 = try #require(await f.waitForTransport(1))
        t1.serverReady(session: "s1", resumed: true, lastMicSeq: 1)  // le serveur n'a reçu que le 1
        #expect(await eventually { t1.sentMicSeqs.count == 2 })
        #expect(t1.sentMicSeqs == [2, 3])
        await client.stop()
    }

    @Test("end_of_speech demandé hors ligne : envoyé après l'audio qui le précède")
    func endOfSpeechOrdering() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f)
        await client.start()
        await client.sendMic(pcm(1))
        await client.sendMic(pcm(2))
        await client.endOfSpeech(meta: ["transcript": .string("x")])
        await client.sendMic(pcm(3))
        let t = try #require(await f.waitForTransport(0))
        t.serverReady()
        #expect(await eventually { t.sentTrace.count == 5 })
        #expect(t.sentTrace == ["hello", "mic1", "mic2", "end_of_speech", "mic3"])
        await client.stop()
    }

    // MARK: reconnexion et reprise

    @Test("coupure → nouvelle connexion avec session_id et last_seq")
    func resumeHello() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f, token: "tk")
        let rec = EventRecorder.record(client.events)
        await client.start()
        let t0 = try #require(await f.waitForTransport(0))
        t0.serverReady(session: "sess-A")
        t0.serverSend(#"{"type":"transcript","seq":1,"text":"a","lang":"fra","confidence":1}"#)
        t0.serverSend(#"{"type":"tts_start","seq":2,"utterance_id":2,"latency_ms":1,"sample_rate":16000}"#)
        t0.serverSend(audio: 3)
        #expect(await eventually { await rec.serverEvents.count == 2 })
        t0.serverDrop()
        let t1 = try #require(await f.waitForTransport(1))
        #expect(await eventually { !t1.sentJSON.isEmpty })
        let hello = t1.sentJSON[0]
        #expect(hello["session_id"] as? String == "sess-A")
        #expect(hello["last_seq"] as? Int == 3)  // l'audio compte dans la numérotation
        #expect(hello["token"] as? String == "tk")
        #expect(await eventually { await rec.states.contains { if case .reconnecting = $0 { true } else { false } } })
        t1.serverReady(session: "sess-A", resumed: true)
        #expect(await eventually { await rec.states.last == .open(resumed: true) })
        await client.stop()
    }

    @Test("le délai de reconnexion suit le backoff et repart de zéro après ready")
    func reconnectsRepeatedly() async throws {
        let f = FakeTransportFactory(failOpenFirst: 3)
        let client = try makeClient(factory: f)
        await client.start()
        // 3 ouvertures échouent, la 4ᵉ aboutit : le client a donc réessayé seul.
        let t = try #require(await f.waitForTransport(3))
        t.serverReady()
        #expect(await eventually { await client.isReadyForTests })
        #expect(f.count == 4)
        await client.stop()
    }

    @Test("rejeu : les doublons (seq déjà vus) sont ignorés, texte et audio")
    func duplicatesIgnored() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f)
        let rec = EventRecorder.record(client.events)
        let audio = DataRecorder.record(client.audio)
        await client.start()
        let t0 = try #require(await f.waitForTransport(0))
        t0.serverReady()
        t0.serverSend(#"{"type":"tts_start","seq":1,"utterance_id":1,"latency_ms":1,"sample_rate":16000}"#)
        t0.serverSend(audio: 2, Data([2, 0]))
        t0.serverSend(audio: 2, Data([9, 9]))  // doublon
        t0.serverSend(audio: 3, Data([3, 0]))
        #expect(await eventually { await audio.chunks.count == 2 })
        t0.serverDrop()
        let t1 = try #require(await f.waitForTransport(1))
        t1.serverReady(resumed: true)
        t1.serverSend(#"{"type":"tts_start","seq":1,"utterance_id":1,"latency_ms":1,"sample_rate":16000}"#)  // rejeu
        t1.serverSend(audio: 3, Data([3, 0]))  // rejeu
        t1.serverSend(audio: 4, Data([4, 0]))  // nouveau
        t1.serverSend(#"{"type":"tts_end","seq":5,"utterance_id":1,"interrupted":false}"#)
        #expect(await eventually { await rec.serverEvents.count == 2 })
        #expect(await eventually { await audio.chunks.count == 3 })
        #expect(await audio.chunks == [Data([2, 0]), Data([3, 0]), Data([4, 0])])
        #expect(await rec.serverEvents == [
            .ttsStart(utteranceID: 1, sampleRate: 16000, latencyMs: 1),
            .ttsEnd(utteranceID: 1, interrupted: false),
        ])
        await client.stop()
    }

    @Test("session neuve après expiration : lastSeq remis à zéro")
    func newSessionResetsSeq() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f)
        let rec = EventRecorder.record(client.events)
        await client.start()
        let t0 = try #require(await f.waitForTransport(0))
        t0.serverReady(session: "old")
        t0.serverSend(#"{"type":"interrupted","seq":50}"#)
        #expect(await eventually { await rec.serverEvents.count == 1 })
        t0.serverDrop()
        let t1 = try #require(await f.waitForTransport(1))
        t1.serverReady(session: "new", resumed: false)  // le serveur a oublié l'ancienne session
        t1.serverSend(#"{"type":"interrupted","seq":1}"#)
        #expect(await eventually { await rec.serverEvents.count == 2 })
        #expect(await eventually { await rec.states.contains(.open(resumed: false)) })
        await client.stop()
    }

    @Test("replayed est transmis à l'UI avec l'indicateur de trou")
    func replayedGap() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f)
        let rec = EventRecorder.record(client.events)
        await client.start()
        let t = try #require(await f.waitForTransport(0))
        t.serverReady(resumed: true)
        t.serverSend(#"{"type":"replayed","count":4,"gap":true}"#)
        #expect(await eventually { await rec.events.contains(.replayGap(count: 4, gap: true)) })
        await client.stop()
    }

    // MARK: erreurs

    @Test("erreurs définitives : état failed, aucune reconnexion", arguments: [
        ("unauthorized", AVEFatalError.unauthorized),
        ("too_many_sessions", .tooManySessions),
        ("bad_version", .badVersion),
        ("unsupported_codec", .unsupportedCodec),
    ])
    func fatalErrors(code: String, expected: AVEFatalError) async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f)
        let rec = EventRecorder.record(client.events)
        await client.start()
        let t = try #require(await f.waitForTransport(0))
        t.serverSend(#"{"type":"error","code":"\#(code)","message":"m"}"#)
        t.serverDrop()  // le serveur ferme en 1008 après l'erreur
        #expect(await eventually { await rec.states.last == .failed(expected) })
        await settle(150)
        #expect(f.count == 1)
        await client.stop()
    }

    @Test("erreur non définitive : transmise à l'UI puis reconnexion")
    func nonFatalError() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f)
        let rec = EventRecorder.record(client.events)
        await client.start()
        let t = try #require(await f.waitForTransport(0))
        t.serverSend(#"{"type":"error","code":"bad_frame","message":"m"}"#)
        t.serverDrop()
        #expect(await eventually { f.count == 2 })
        #expect(await rec.serverEvents.contains(.error(code: "bad_frame", message: "m")))
        await client.stop()
    }

    @Test("événement inconnu ou mal formé : ignoré, la session continue")
    func unknownAndMalformedIgnored() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f)
        let rec = EventRecorder.record(client.events)
        await client.start()
        let t = try #require(await f.waitForTransport(0))
        t.serverReady()
        t.serverSend(#"{"type":"evenement_du_futur","seq":1,"x":1}"#)
        t.serverSend(#"{"type":"tts_start","seq":2}"#)  // malformé
        t.serverSend("pas du json")
        t.serverSend(#"{"type":"interrupted","seq":3}"#)
        #expect(await eventually { await rec.serverEvents == [.interrupted] })
        #expect(f.count == 1)
        await client.stop()
    }

    // MARK: ping, arrêt

    @Test("ping applicatif périodique une fois ready")
    func pings() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f, ping: .milliseconds(20))
        await client.start()
        let t = try #require(await f.waitForTransport(0))
        #expect(await eventually { t.sentJSON.filter { $0["type"] as? String == "ping" }.isEmpty })
        t.serverReady()
        #expect(await eventually { t.sentJSON.filter { $0["type"] as? String == "ping" }.count >= 2 })
        await client.stop()
    }

    @Test("stop : bye envoyé, socket fermée, pas de reconnexion")
    func stopSendsBye() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f)
        let rec = EventRecorder.record(client.events)
        await client.start()
        let t = try #require(await f.waitForTransport(0))
        t.serverReady()
        #expect(await eventually { await client.isReadyForTests })
        await client.stop()
        #expect(t.sentJSON.contains { $0["type"] as? String == "bye" })
        #expect(t.isClosed)
        await settle(100)
        #expect(f.count == 1)
        #expect(await eventually { await rec.states.last == .closed })
    }

    @Test("interrupt : envoyé en ligne, abandonné hors ligne")
    func interrupt() async throws {
        let f = FakeTransportFactory()
        let client = try makeClient(factory: f)
        await client.start()
        await client.interrupt()  // hors ligne : perdu volontairement
        let t = try #require(await f.waitForTransport(0))
        t.serverReady()
        #expect(await eventually { await client.isReadyForTests })
        #expect(!t.sentJSON.contains { $0["type"] as? String == "interrupt" })
        await client.interrupt()
        #expect(await eventually { t.sentJSON.contains { $0["type"] as? String == "interrupt" } })
        await client.stop()
    }
}

extension AVEWebSocketClient {
    /// Accès de test à l'état « ready ».
    var isReadyForTests: Bool { isReadyState }
}
