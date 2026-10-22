import AVECore
import Foundation
import Observation

public enum SessionMode: Sendable, Equatable {
    case voice, text
}

/// Une session AVE, deux modes (voix / texte). Relie le client WebSocket, l'audio, la machine du
/// barge-in et la conversation. Passer de la voix au texte coupe le micro mais NE ferme PAS la session.
@MainActor
@Observable
public final class SessionCoordinator {
    public struct Configuration: Sendable {
        public var vad = VoiceActivityDetector.Config()
        /// Trames conservées avant la détection de parole (10 = 200 ms).
        public var preRollFrames = 10
        /// Sans réponse après `end_of_speech` au bout de ce délai, le tour est abandonné.
        public var turnTimeout: Duration = .seconds(20)
        /// Faux pour désactiver la saisie texte avec un serveur qui ne gère pas `text`.
        public var supportsTextInput = true
        /// Plafond de mémoire pour l'audio mis en cache (« réécouter »).
        public var replayCacheBytes = 4_000_000

        public init() {}
    }

    // État observable par l'UI
    public private(set) var transcript = ChatTranscript()
    public private(set) var phase: BargeInStateMachine.Phase = .idle
    public private(set) var connection: ConnectionState = .idle
    public private(set) var mode: SessionMode
    public private(set) var micLevel: Float = 0
    public private(set) var playbackLevel: Float = 0
    /// Dernier message d'état à montrer (erreur, perte de données…). `nil` = rien à signaler.
    public private(set) var notice: String?
    public private(set) var replayingMessageID: Int?
    /// Langues avec leur disponibilité réelle (`ready.languages`), sinon la liste de repli.
    public private(set) var languageOptions: [LanguageOption] = LanguageCatalog.builtIn

    public var orbState: OrbState { OrbState(phase: phase, connection: connection) }
    public var supportsTextInput: Bool { configuration.supportsTextInput }

    /// Appelé APRÈS accord explicite de l'utilisateur (ou si le serveur dit `confirm: false`).
    @ObservationIgnored public var onAction: (@MainActor (ActionCard) -> Void)?

    @ObservationIgnored private let client: AVEWebSocketClient
    @ObservationIgnored private let devices: AudioDevices
    @ObservationIgnored private let configuration: Configuration
    @ObservationIgnored private let activity: (any SessionActivityPresenting)?
    @ObservationIgnored private var activityStarted = false
    @ObservationIgnored private var lastActivityPhase: LiveActivityPhase?
    @ObservationIgnored private var machine = BargeInStateMachine()
    @ObservationIgnored private var vad: VoiceActivityDetector
    @ObservationIgnored private var preRoll: PreRollBuffer
    @ObservationIgnored private var micSmoother = LevelSmoother()
    @ObservationIgnored private var gateOpen = false
    @ObservationIgnored private var micRunning = false
    @ObservationIgnored private var hasBeenOpen = false
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var turnTimer: Task<Void, Never>?
    @ObservationIgnored private var utteranceChunks: [Data] = []
    @ObservationIgnored private var replayCache: [(id: Int, chunks: [Data], bytes: Int)] = []

    public init(client: AVEWebSocketClient, devices: AudioDevices, mode: SessionMode = .voice,
                configuration: Configuration = Configuration(), activity: (any SessionActivityPresenting)? = nil) {
        self.activity = activity
        self.client = client
        self.devices = devices
        self.mode = mode
        self.configuration = configuration
        self.vad = VoiceActivityDetector(config: configuration.vad)
        self.preRoll = PreRollBuffer(capacity: configuration.preRollFrames)
    }

    // MARK: Cycle de vie

    public func start() async {
        guard tasks.isEmpty else { return }
        do { try devices.lifecycle.activate() } catch {
            notice = UserMessages.audioUnavailable
            mode = .text
        }
        await client.start()
        tasks = [
            Task { [weak self] in
                guard let events = self?.client.events else { return }
                for await e in events { await self?.handle(e) }
            },
            Task { [weak self] in
                guard let frames = self?.devices.mic.frames else { return }
                for await f in frames { await self?.handleMic(f) }
            },
            Task { [weak self] in
                guard let levels = self?.devices.player.levels else { return }
                for await l in levels { self?.playbackLevel = l }
            },
            Task { [weak self] in
                guard let events = self?.devices.lifecycle.events else { return }
                for await e in events { await self?.handle(e) }
            },
        ]
        if mode == .voice { await startMic() }
    }

    public func stop() async {
        for t in tasks { t.cancel() }
        tasks = []
        turnTimer?.cancel()
        stopMic()
        devices.player.purge()
        devices.lifecycle.deactivate()
        if activityStarted {
            activity?.end()
            activityStarted = false
        }
        await client.stop()
    }

    // MARK: Actions de l'utilisateur

    public func setMode(_ new: SessionMode) async {
        guard new != mode else { return }
        if new == .text {
            await closeUserTurnIfOpen()
            stopMic()
            await interruptAssistant()
            mode = .text
        } else {
            mode = .voice
            await startMic()
        }
    }

    /// Coupe la voix de l'assistant (bouton, orbe). Sans effet s'il ne parle pas.
    public func interruptAssistant() async {
        await perform(machine.handle(.manualInterrupt))
        syncPhase()
    }

    /// Envoie un message texte. La bulle de l'utilisateur apparaît à l'écho `transcript {source:"text"}`
    /// du serveur, comme pour la voix. Parler pendant ce temps vaut barge-in côté serveur.
    public func sendText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard supportsTextInput else {
            notice = UserMessages.textInputUnavailable
            return
        }
        guard trimmed.count <= 4000 else {
            notice = UserMessages.textTooLong
            return
        }
        if await client.sendText(trimmed) {
            if replayingMessageID != nil { stopReplay() }
            await perform(machine.handle(.userSentText))
        } else {
            notice = UserMessages.notConnected
        }
    }

    public func setLanguage(_ language: AVELanguage) async {
        await client.setLanguage(language)
    }

    public func confirmAction(messageID: Int) {
        if let card = transcript.resolveCard(messageID: messageID, confirmed: true) { onAction?(card) }
    }

    public func declineAction(messageID: Int) {
        transcript.resolveCard(messageID: messageID, confirmed: false)
    }

    public func dismissNotice() { notice = nil }

    /// Rejoue l'audio mis en cache d'une réponse (le serveur n'a pas de message `speak`, contrat E7).
    public func replay(messageID: Int) {
        guard phase == .idle || phase == .listening, replayingMessageID == nil,
              let entry = replayCache.first(where: { $0.id == messageID }) else { return }
        replayingMessageID = messageID
        for chunk in entry.chunks { devices.player.enqueue(chunk) }
        devices.player.endOfUtterance()
        Task { [weak self] in
            // Attend la fin de la lecture (sondage court, borné à 2 minutes).
            for _ in 0..<1_200 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.replayingMessageID == messageID else { return }
                if self.devices.player.isDrained { break }
            }
            self?.replayingMessageID = nil
        }
    }

    public func hasCachedAudio(for messageID: Int) -> Bool {
        replayCache.contains { $0.id == messageID }
    }

    // MARK: Micro

    private func startMic() async {
        guard !micRunning else { return }
        guard await devices.lifecycle.requestMicrophonePermission() else {
            notice = UserMessages.microphoneDenied
            mode = .text
            return
        }
        micRunning = true
        devices.mic.start()
    }

    private func stopMic() {
        guard micRunning else { return }
        micRunning = false
        devices.mic.stop()
        vad.reset()
        _ = preRoll.drain()
        micLevel = 0
    }

    /// Si l'utilisateur parlait quand on quitte le mode vocal, on clôt proprement son énoncé.
    private func closeUserTurnIfOpen() async {
        guard gateOpen else { return }
        gateOpen = false
        await perform(machine.handle(.userSpeechEnded))
        syncPhase()
    }

    private func handleMic(_ frame: MicFrame) async {
        guard mode == .voice, micRunning else { return }
        micLevel = micSmoother.next(AudioLevel.normalized(rms: frame.rms))
        let audible = phase == .speaking || replayingMessageID != nil || !devices.player.isDrained
        switch vad.process(rms: frame.rms, assistantSpeaking: audible) {
        case .speechStarted:
            if replayingMessageID != nil { stopReplay() }
            await perform(machine.handle(.userSpeechStarted))  // barge-in si l'assistant parlait
            gateOpen = true
            for old in preRoll.drain() { await client.sendMic(old) }
            await client.sendMic(frame.pcm)
        case .speechEnded:
            gateOpen = false
            await client.sendMic(frame.pcm)
            await perform(machine.handle(.userSpeechEnded))
        case nil:
            if gateOpen { await client.sendMic(frame.pcm) } else { preRoll.push(frame.pcm) }
        }
        syncPhase()
    }

    // MARK: Réseau

    private func handle(_ event: ClientEvent) async {
        switch event {
        case .state(let state):
            connection = state
            switch state {
            case .open(let resumed):
                if !resumed && hasBeenOpen { notice = UserMessages.sessionRestarted }
                hasBeenOpen = true
            case .failed(let error):
                notice = UserMessages.fatal(error)
                await perform(machine.handle(.sessionLost))
            case .closed:
                await perform(machine.handle(.sessionLost))
            case .idle, .connecting, .reconnecting:
                break
            }
        case .ready(let ready):
            languageOptions = LanguageCatalog.options(from: ready.languages)
        case .audio(let data):
            handleAudio(data)
        case .replayGap(_, let gap):
            if gap { notice = UserMessages.responseTruncated }
        case .server(let e):
            await handle(server: e)
        }
        syncPhase()
    }

    private func handle(server event: ServerEvent) async {
        switch event {
        case .ttsStart:
            utteranceChunks = []
            await perform(machine.handle(.ttsStarted))
            transcript.apply(event)
        case .ttsEnd(_, let interrupted):
            let id = transcript.currentAssistantID
            await perform(machine.handle(.ttsEnded(interrupted: interrupted)))
            if !interrupted {
                devices.player.endOfUtterance()
                if let id { cache(chunks: utteranceChunks, for: id) }
            }
            utteranceChunks = []
        case .turnEnd(_, let interrupted):
            await perform(machine.handle(.turnEnded(interrupted: interrupted)))
            transcript.apply(event)
        case .interrupted:
            await perform(machine.handle(.serverInterrupted))
            transcript.apply(event)
        case .turnError:
            await perform(machine.handle(.turnFailed))
            transcript.apply(event)
        case .action, .replyText, .transcript:
            if let auto = transcript.apply(event), let card = auto.card { onAction?(card) }
        default:
            break
        }
    }

    private func handleAudio(_ data: Data) {
        guard machine.acceptsTTSAudio else { return }  // reliquat d'un énoncé annulé
        utteranceChunks.append(data)
        devices.player.enqueue(data)
    }

    // MARK: Session audio (appel entrant, débranchement…)

    private func handle(_ event: AudioSessionEvent) async {
        switch event {
        case .interruptionBegan:
            await closeUserTurnIfOpen()
            stopMic()
            await interruptAssistant()
            devices.player.purge()
        case .interruptionEnded(let shouldResume):
            if shouldResume, (try? devices.lifecycle.activate()) != nil, mode == .voice { await startMic() }
        case .routeChanged(_, let reason):
            if reason == .oldDeviceUnavailable { await interruptAssistant() }
        case .mediaServicesReset:
            stopMic()
            if (try? devices.lifecycle.activate()) != nil, mode == .voice { await startMic() }
        }
    }

    // MARK: Moteur de décisions

    private func perform(_ actions: [BargeInStateMachine.Action]) async {
        for action in actions {
            switch action {
            case .purgePlayback: devices.player.purge()
            case .sendInterrupt: await client.interrupt()
            case .sendEndOfSpeech: await client.endOfSpeech()
            }
        }
        syncPhase()
    }

    private func stopReplay() {
        replayingMessageID = nil
        devices.player.purge()
    }

    /// Live Activity : démarre à l'ouverture de la session, ne reçoit que les CHANGEMENTS d'état, s'arrête quand la session est perdue.
    private func refreshActivity() {
        guard let activity else { return }
        guard let current = LiveActivityPhase(orb: orbState) else {
            if activityStarted {
                activity.end()
                activityStarted = false
                lastActivityPhase = nil
            }
            return
        }
        if !activityStarted {
            guard case .open = connection else { return }
            activity.start()
            activityStarted = true
            lastActivityPhase = nil
        }
        if current != lastActivityPhase {
            lastActivityPhase = current
            activity.update(current)
        }
    }

    private func syncPhase() {
        phase = machine.phase
        refreshActivity()
        if phase == .thinking {
            guard turnTimer == nil else { return }
            let timeout = configuration.turnTimeout
            turnTimer = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                await self?.turnTimedOut()
            }
        } else {
            turnTimer?.cancel()
            turnTimer = nil
        }
    }

    private func turnTimedOut() async {
        turnTimer = nil
        guard machine.phase == .thinking else { return }
        _ = machine.handle(.turnFailed)
        transcript.appendSystem(UserMessages.noResponse)
        syncPhase()
    }

    private func cache(chunks: [Data], for id: Int) {
        let bytes = chunks.reduce(0) { $0 + $1.count }
        guard bytes > 0, bytes <= configuration.replayCacheBytes else { return }
        replayCache.removeAll { $0.id == id }
        replayCache.append((id, chunks, bytes))
        while replayCache.reduce(0, { $0 + $1.bytes }) > configuration.replayCacheBytes, replayCache.count > 1 {
            replayCache.removeFirst()
        }
    }
}
