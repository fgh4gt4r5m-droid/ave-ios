import Foundation

/// Client WebSocket AVE : hello/ready, reprise de session, reconnexion avec backoff, file micro
/// bornée, ping applicatif. Un client = une session (créer un nouveau client pour une autre).
public actor AVEWebSocketClient {
    public struct Configuration: Sendable {
        public var endpoint: AVEEndpoint
        public var lang: AVELanguage
        public var sampleRate: Int
        public var backoff: Backoff
        public var pingInterval: Duration
        /// Sans trame reçue depuis ce délai, la connexion est jugée morte et recréée. `nil` = désactivé.
        public var deadPeerTimeout: Duration?
        public var micQueueCapacity: Int
        public var clientInfo: ClientInfo?

        public init(endpoint: AVEEndpoint, lang: AVELanguage = .auto, sampleRate: Int = 16_000,
                    backoff: Backoff = Backoff(), pingInterval: Duration = .seconds(15),
                    deadPeerTimeout: Duration? = .seconds(45), micQueueCapacity: Int = 500,
                    clientInfo: ClientInfo? = nil) {
            self.clientInfo = clientInfo
            self.endpoint = endpoint
            self.lang = lang
            self.sampleRate = sampleRate
            self.backoff = backoff
            self.pingInterval = pingInterval
            self.deadPeerTimeout = deadPeerTimeout
            self.micQueueCapacity = micQueueCapacity
        }
    }

    /// État, événements de protocole, erreurs ET audio TTS, dans l'ordre exact de réception : un seul
    /// flux garantit qu'un chunk n'est jamais traité avant le `tts_start` qui le précède.
    public nonisolated let events: AsyncStream<ClientEvent>

    private let config: Configuration
    private let tokenProvider: AVETokenProvider
    private let transportFactory: TransportFactory
    private let log: AVELogger
    private let eventsOut: AsyncStream<ClientEvent>.Continuation

    private var runTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var transport: (any WebSocketTransport)?
    private var stopped = false
    private var isReady = false
    private var fatal: AVEFatalError?

    private var language: AVELanguage
    private var sessionID: String?
    private var lastSeq: UInt32 = 0
    private var micSeq: UInt32 = 0
    private var micQueue: [(seq: UInt32, frame: Data)] = []
    /// `end_of_speech` demandés hors ligne ; `afterMicSeq` = dernier chunk micro qui les précède.
    private var pendingEndOfSpeech: [(afterMicSeq: UInt32, meta: [String: JSONValue]?)] = []
    private var reconnectAttempt = 0
    private var lastInbound = ContinuousClock.now

    public init(configuration: Configuration,
                tokenProvider: @escaping AVETokenProvider = { nil },
                transportFactory: @escaping TransportFactory = URLSessionWebSocketTransport.factory,
                logger: AVELogger = .silent) {
        self.config = configuration
        self.language = configuration.lang
        self.tokenProvider = tokenProvider
        self.transportFactory = transportFactory
        self.log = logger
        let (events, eventsOut) = AsyncStream<ClientEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = events
        self.eventsOut = eventsOut
    }

    // MARK: API publique

    /// Vrai quand `ready` est reçu et la file micro renvoyée (utile aux tests et à l'UI de debug).
    var isReadyState: Bool { isReady }

    public func start() {
        guard runTask == nil, !stopped else { return }
        runTask = Task { [weak self] in await self?.runLoop() }
    }

    /// Envoie un chunk PCM16 (≈ 20 ms). Conservé dans la file bornée tant que la socket n'est pas prête.
    public func sendMic(_ pcm: Data) async {
        guard !stopped, fatal == nil else { return }
        micSeq &+= 1
        let frame = AudioFrame(kind: .mic, seq: micSeq, payload: pcm).encoded()
        micQueue.append((micSeq, frame))
        if micQueue.count > config.micQueueCapacity {
            micQueue.removeFirst(micQueue.count - config.micQueueCapacity)
        }
        if isReady { await send(.binary(frame)) }
    }

    public func endOfSpeech(meta: [String: JSONValue]? = nil) async {
        if isReady {
            await send(message: .endOfSpeech(meta: meta))
        } else if !stopped, fatal == nil {
            pendingEndOfSpeech.append((micSeq, meta))  // partira après le renvoi de l'audio manquant
        }
    }

    /// Envoie un message texte (1–4000 caractères). Renvoie `false` s'il n'a pas pu partir (hors ligne,
    /// vide ou trop long) : l'appelant doit le dire à l'utilisateur, pas le perdre en silence.
    @discardableResult
    public func sendText(_ text: String) async -> Bool {
        guard isReady, (1...4000).contains(text.count) else { return false }
        await send(message: .text(text))
        return true
    }

    /// Synthèse à la demande (≤ 1000 caractères).
    @discardableResult
    public func speak(_ text: String, lang: AVELanguage? = nil) async -> Bool {
        guard isReady, (1...1000).contains(text.count) else { return false }
        await send(message: .speak(text: text, lang: lang))
        return true
    }

    /// Réponse à la demande d'aide. Renvoie `false` si le message n'a pas pu partir (hors ligne).
    @discardableResult
    public func sendLearningConsent(granted: Bool, version: String) async -> Bool {
        guard isReady, !version.isEmpty else { return false }
        await send(message: .learningConsent(granted: granted, version: version))
        return true
    }

    @discardableResult
    public func revokeLearning() async -> Bool {
        guard isReady else { return false }
        await send(message: .learningRevoke)
        return true
    }

    /// Retour 👍/👎 (correction ≤ 1000 caractères ; au-delà le serveur ferme la session avec `bad_feedback`, donc on refuse ici).
    @discardableResult
    public func sendFeedback(utteranceID: Int?, rating: FeedbackRating, correction: String? = nil) async -> Bool {
        guard isReady else { return false }
        let trimmed = correction?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, trimmed.count > 1000 { return false }
        await send(message: .feedback(utteranceID: utteranceID, rating: rating, correction: (trimmed?.isEmpty ?? true) ? nil : trimmed))
        return true
    }

    /// Change la langue de la session ; mémorisée pour les reconnexions.
    public func setLanguage(_ new: AVELanguage) async {
        language = new
        if isReady { await send(message: .setLanguage(new)) }
    }

    /// Hors ligne, un `interrupt` est périmé à la reconnexion : on ne le met pas en file.
    public func interrupt() async {
        if isReady { await send(message: .interrupt) }
    }

    public func stop() async {
        guard !stopped else { return }
        if isReady { await send(message: .bye) }
        stopped = true
        isReady = false
        pingTask?.cancel()
        runTask?.cancel()
        transport?.close()
        transport = nil
        if fatal == nil { eventsOut.yield(.state(.closed)) }
        eventsOut.finish()
    }

    // MARK: Boucle de connexion

    private func runLoop() async {
        var first = true
        while !stopped && !Task.isCancelled {
            eventsOut.yield(.state(first ? .connecting : .reconnecting(attempt: reconnectAttempt)))
            first = false
            await runConnection()
            isReady = false
            pingTask?.cancel()
            pingTask = nil
            if stopped || Task.isCancelled { return }
            if let fatal {
                log.error("fatal error: \(fatal.rawValue)")
                eventsOut.yield(.state(.failed(fatal)))
                eventsOut.finish()
                return
            }
            // Le compteur repart de zéro à chaque `ready` (voir handleReady).
            let wait = config.backoff.delay(forAttempt: reconnectAttempt)
            reconnectAttempt += 1
            log.info("reconnecting, attempt \(reconnectAttempt)")
            do { try await Task.sleep(for: wait) } catch { return }
        }
    }

    private func runConnection() async {
        let t = transportFactory(config.endpoint.url)
        transport = t
        do {
            try await t.open()
            // Peut aller chercher un jeton frais auprès de l'hôte (WoYo, TaGa…) ; une erreur ici
            // fait échouer la tentative, qui sera rejouée avec le backoff.
            let token = try await tokenProvider()
            let hello = ClientMessage.Hello(
                lang: language, sampleRate: config.sampleRate,
                sessionID: sessionID, lastSeq: sessionID == nil ? nil : lastSeq,
                token: token, vad: .client, client: config.clientInfo)
            try await t.send(.text(ClientMessage.hello(hello).jsonString()))
            lastInbound = .now
            for try await message in t.incoming {
                lastInbound = .now
                await handle(message)
                if fatal != nil { break }
            }
        } catch {
            log.info("connection ended: \(type(of: error))")
        }
        t.close()
        transport = nil
    }

    // MARK: Réception

    private func handle(_ message: TransportMessage) async {
        switch message {
        case .binary(let data):
            do {
                let frame = try AudioFrame.decode(data)
                guard frame.kind == .tts else { return }
                guard accept(seq: frame.seq) else { return }
                eventsOut.yield(.audio(frame.payload))
            } catch {
                log.error("bad binary frame")
            }
        case .text(let text):
            let frame: ServerFrame
            do { frame = try ServerFrame.decode(text) } catch {
                log.error("undecodable event ignored")
                return
            }
            if let seq = frame.seq, !accept(seq: seq) { return }
            await handle(event: frame.event)
        }
    }

    /// Dédoublonnage : un `seq` déjà vu (rejeu après reprise) est ignoré.
    private func accept(seq: UInt32) -> Bool {
        guard seq > lastSeq else { return false }
        lastSeq = seq
        return true
    }

    private func handle(event: ServerEvent) async {
        switch event {
        case .ready(let r):
            await handleReady(r)
            eventsOut.yield(.ready(r))
            eventsOut.yield(.state(.open(resumed: r.resumed)))
        case .replayed(let count, let gap):
            eventsOut.yield(.replayGap(count: count, gap: gap))
        case .pong:
            break
        case .error(let code, _):
            if let f = AVEFatalError(code: code) {
                fatal = f
            } else {
                log.error("server error: \(code)")
                eventsOut.yield(.server(event))
            }
        case .unknown(let type):
            log.info("unknown event type ignored: \(type)")
        default:
            eventsOut.yield(.server(event))
        }
    }

    private func handleReady(_ r: ServerEvent.Ready) async {
        reconnectAttempt = 0
        sessionID = r.sessionID
        if !r.resumed {
            // Session neuve (la précédente a expiré, ou première connexion) : la numérotation
            // serveur repart de zéro ; garder l'ancien lastSeq ferait ignorer toutes les réponses.
            lastSeq = 0
        }
        // Renvoi dans l'ordre : micro manquant (seq > last_mic_seq) et end_of_speech en attente.
        // `isReady` ne passe à vrai qu'une fois tout renvoyé : un chunk produit pendant le renvoi
        // est ajouté à la file et repris par cette boucle, donc jamais envoyé avant les anciens
        // (le serveur écarte tout seq <= last_mic_seq comme doublon).
        var sentMic = r.lastMicSeq
        while true {
            let nextMic = micQueue.first { $0.seq > sentMic }
            if let eos = pendingEndOfSpeech.first, nextMic.map({ $0.seq > eos.afterMicSeq }) ?? true {
                pendingEndOfSpeech.removeFirst()
                await send(message: .endOfSpeech(meta: eos.meta))
            } else if let mic = nextMic {
                sentMic = mic.seq
                await send(.binary(mic.frame))
            } else {
                break
            }
        }
        isReady = true
        startPing()
    }

    // MARK: Envoi et ping

    private func send(message: ClientMessage) async {
        do {
            let text = try message.jsonString()
            await send(.text(text))
        } catch {
            log.error("encode failed")
        }
    }

    private func send(_ message: TransportMessage) async {
        guard let transport else { return }
        do { try await transport.send(message) } catch {
            log.info("send failed, connection will be recreated")
            transport.close()  // termine `incoming` → la boucle reconnecte
        }
    }

    private func startPing() {
        pingTask?.cancel()
        let interval = config.pingInterval
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                await self?.pingTick()
            }
        }
    }

    private func pingTick() async {
        guard isReady else { return }
        if let timeout = config.deadPeerTimeout, ContinuousClock.now - lastInbound > timeout {
            log.info("dead peer detected")
            transport?.close()
            return
        }
        await send(message: .ping(t: (Date().timeIntervalSince1970 * 1000).rounded()))
    }
}
