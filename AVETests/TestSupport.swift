import Foundation
@testable import AVECore

/// Faux transport : le test joue le rôle du serveur.
final class FakeWebSocketTransport: WebSocketTransport, @unchecked Sendable {
    struct OpenFailure: Error {}

    let incoming: AsyncThrowingStream<TransportMessage, Error>
    private let continuation: AsyncThrowingStream<TransportMessage, Error>.Continuation
    private let lock = NSLock()
    private var _sent: [TransportMessage] = []
    private var _closed = false
    private let failOpen: Bool

    init(failOpen: Bool = false) {
        self.failOpen = failOpen
        let (stream, continuation) = AsyncThrowingStream<TransportMessage, Error>.makeStream()
        self.incoming = stream
        self.continuation = continuation
    }

    func open() async throws {
        if failOpen { throw OpenFailure() }
    }

    func send(_ message: TransportMessage) async throws {
        try lock.withLock {
            if _closed { throw OpenFailure() }
            _sent.append(message)
        }
    }

    func close() {
        lock.withLock { _closed = true }
        continuation.finish()
    }

    // Côté « serveur »
    func serverSend(_ json: String) { continuation.yield(.text(json)) }
    func serverSend(audio seq: UInt32, _ payload: Data = Data([1, 0])) {
        continuation.yield(.binary(AudioFrame(kind: .tts, seq: seq, payload: payload).encoded()))
    }
    func serverDrop() { continuation.finish(throwing: OpenFailure()) }
    func serverReady(session: String = "s1", resumed: Bool = false, lastMicSeq: UInt32 = 0, languages: String? = nil) {
        let extra = languages.map { #","grace_s":30,"languages":\#($0)"# } ?? ""
        serverSend(#"{"type":"ready","session_id":"\#(session)","resumed":\#(resumed),"last_mic_seq":\#(lastMicSeq),"seq":0,"protocol":1\#(extra)}"#)
    }

    var sent: [TransportMessage] { lock.withLock { _sent } }
    var isClosed: Bool { lock.withLock { _closed } }

    /// Messages texte envoyés, décodés en dictionnaire.
    var sentJSON: [[String: Any]] {
        sent.compactMap {
            guard case .text(let s) = $0 else { return nil }
            return (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
        }
    }

    var sentMicSeqs: [UInt32] {
        sent.compactMap {
            guard case .binary(let d) = $0, let f = try? AudioFrame.decode(d), f.kind == .mic else { return nil }
            return f.seq
        }
    }

    /// Ordre exact des envois, pour vérifier micro vs end_of_speech.
    var sentTrace: [String] {
        sent.compactMap {
            switch $0 {
            case .binary(let d):
                guard let f = try? AudioFrame.decode(d) else { return nil }
                return "mic\(f.seq)"
            case .text(let s):
                guard let o = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any],
                      let t = o["type"] as? String else { return nil }
                return t
            }
        }
    }
}

final class FakeTransportFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var _transports: [FakeWebSocketTransport] = []
    private var failOpenFirst: Int
    private var _urls: [URL] = []

    init(failOpenFirst: Int = 0) { self.failOpenFirst = failOpenFirst }

    var factory: TransportFactory {
        { [self] url in
            lock.withLock {
                let t = FakeWebSocketTransport(failOpen: failOpenFirst > 0)
                if failOpenFirst > 0 { failOpenFirst -= 1 }
                _transports.append(t)
                _urls.append(url)
                return t
            }
        }
    }

    var count: Int { lock.withLock { _transports.count } }
    var urls: [URL] { lock.withLock { _urls } }
    func transport(_ i: Int) -> FakeWebSocketTransport? {
        lock.withLock { i < _transports.count ? _transports[i] : nil }
    }

    /// Attend la i-ème connexion puis la renvoie.
    func waitForTransport(_ i: Int) async -> FakeWebSocketTransport? {
        _ = await eventually { self.count > i }
        return transport(i)
    }
}

actor EventRecorder {
    private(set) var events: [ClientEvent] = []
    func append(_ e: ClientEvent) { events.append(e) }

    static func record(_ stream: AsyncStream<ClientEvent>) -> EventRecorder {
        let r = EventRecorder()
        Task { for await e in stream { await r.append(e) } }
        return r
    }

    var states: [ConnectionState] {
        events.compactMap { if case .state(let s) = $0 { return s } else { return nil } }
    }
    var audioChunks: [Data] {
        events.compactMap { if case .audio(let d) = $0 { return d } else { return nil } }
    }
    var serverEvents: [ServerEvent] {
        events.compactMap { if case .server(let s) = $0 { return s } else { return nil } }
    }
}

/// Attend qu'une condition devienne vraie (sondage court, borné).
func eventually(timeout: Duration = .seconds(3), _ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

/// Laisse le temps à d'éventuels effets indésirables de se produire (assertions « ne se passe pas »).
func settle(_ ms: Int = 120) async { try? await Task.sleep(for: .milliseconds(ms)) }
