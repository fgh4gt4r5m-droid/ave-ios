import AVECore
import Foundation
import Observation

public enum SessionMode: Sendable, Equatable {
    case voice, text
}

/// Message écrit hors connexion : affiché « en attente » et envoyé tout seul au retour du réseau (3G instable).
public struct PendingText: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let text: String
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
        /// Nombre de tours terminés avant de proposer l'aide à l'amélioration (l'utilisateur a vu ce que fait l'app).
        public var learningPromptAfterTurns = 1
        public var learningNotices: [LearningNoticeText] = LearningNotice.all
        /// Avis permanent sur l'état réel du moteur (écho, son de test). Fourni par l'app selon sa configuration, et non
        /// codé en dur : le jour où le moteur aura un vrai dialogue, l'avis disparaît sans toucher au code.
        public var demoNotice: String?

        public init() {}
    }

    // État observable par l'UI
    // `internal(set)` (et non `private(set)`) : les fichiers et images vivent dans `SessionCoordinator+Media.swift`.
    public internal(set) var transcript = ChatTranscript()
    public private(set) var phase: BargeInStateMachine.Phase = .idle
    public private(set) var connection: ConnectionState = .idle
    public private(set) var mode: SessionMode
    public private(set) var micLevel: Float = 0
    public private(set) var playbackLevel: Float = 0
    /// Dernier message d'état à montrer (erreur, perte de données…). `nil` = rien à signaler.
    public internal(set) var notice: String?
    public private(set) var replayingMessageID: Int?
    /// Langues avec leur disponibilité réelle (`ready.languages`), sinon la liste de repli.
    public private(set) var languageOptions: [LanguageOption] = LanguageCatalog.builtIn
    /// État de l'apprentissage annoncé par le serveur (`ready.learning`), mis à jour par `learning_state`.
    public private(set) var learning: LearningStatus?
    /// Non `nil` : la notice doit être montrée (feuille modale). Le micro est ignoré tant qu'elle est visible.
    public private(set) var learningPrompt: LearningPrompt?
    /// Message à afficher après une action d'apprentissage (retrait, merci…).
    public private(set) var learningMessage: String?
    /// Messages ayant déjà reçu un 👍/👎 pendant cette session.
    public private(set) var feedbackGiven: Set<Int> = []
    public private(set) var selectedLanguage: AVELanguage
    /// Messages écrits hors connexion, dans l'ordre, envoyés dès que la session est rouverte.
    public private(set) var pendingTexts: [PendingText] = []
    /// Micro coupé en mode vocal (sans quitter le mode vocal) : rien n'est capté ni envoyé.
    public private(set) var micMuted = false
    /// Pièces jointes en cours d'envoi, montrées dans la barre de saisie.
    public internal(set) var attachmentDrafts: [AttachmentDraft] = []
    /// Réglage « Lire les réponses à voix haute » en mode texte. L'audio est TOUJOURS gardé pour « Lire à voix haute ».
    public var autoPlayInTextMode = true
    /// Type de compte de l'app AVE (`nil` : app hôte, WoYo/TaGa…). Un INVITÉ n'est pas sollicité pour l'apprentissage : sa clé de
    /// consentement ne vit que le temps de la session, donc « effacer mes données » ne pourrait pas être tenu pour les sessions passées.
    public var accountKind: AccountKind? {
        didSet { if accountKind == .guest { learningPrompt = nil } }
    }
    /// Faux pour un invité : l'option n'est pas proposée (décision produit en attente, contrat §7).
    public var learningOfferedToUser: Bool { accountKind != .guest }

    public var orbState: OrbState { OrbState(phase: phase, connection: connection) }
    public var supportsTextInput: Bool { configuration.supportsTextInput }
    public var demoNotice: String? { configuration.demoNotice }

    /// Appelé APRÈS accord explicite de l'utilisateur (ou si le serveur dit `confirm: false`).
    @ObservationIgnored public var onAction: (@MainActor (ActionCard) -> Void)?

    @ObservationIgnored let client: AVEWebSocketClient
    /// `nil` : pas de fichiers ni d'images (app hôte, démo hors ligne).
    @ObservationIgnored let media: MediaServices?
    @ObservationIgnored var uploadTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let devices: AudioDevices
    @ObservationIgnored private let configuration: Configuration
    @ObservationIgnored private let learningPreferences: any LearningPreferences
    @ObservationIgnored private var askedLearningThisSession = false
    @ObservationIgnored private var completedTurns = 0
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
    /// Message dont la lecture à voix haute a été demandée au moteur (`speak`), jusqu'à son `turn_end`.
    @ObservationIgnored private var speakingFor: Int?

    public init(client: AVEWebSocketClient, devices: AudioDevices, mode: SessionMode = .voice,
                configuration: Configuration = Configuration(), activity: (any SessionActivityPresenting)? = nil,
                language: AVELanguage = .french, learningPreferences: any LearningPreferences = InMemoryLearningPreferences(),
                accountKind: AccountKind? = nil, transcript: ChatTranscript = ChatTranscript(),
                media: MediaServices? = nil) {
        self.transcript = transcript
        self.media = media
        self.activity = activity
        self.accountKind = accountKind
        self.selectedLanguage = language
        self.learningPreferences = learningPreferences
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
        for upload in uploadTasks.values { upload.cancel() }
        uploadTasks = [:]
        attachmentDrafts = []
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
            micMuted = false
            await startMic()
        }
    }

    /// Couper ou rouvrir le micro sans quitter le mode vocal (bruit, quelqu'un arrive).
    public func setMicMuted(_ muted: Bool) async {
        guard mode == .voice, muted != micMuted else { return }
        micMuted = muted
        if muted {
            await closeUserTurnIfOpen()
            stopMic()
        } else {
            await startMic()
        }
    }

    /// « Réessayer » sur une réponse : renvoie la question qui la précède.
    public func retry(messageID: Int) async {
        let messages = transcript.messages
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              let question = messages[..<index].last(where: { $0.role == .user }) else { return }
        await sendText(question.text)
    }

    /// Envoie dans l'ordre les messages écrits hors connexion ; s'arrête au premier refus (connexion de nouveau perdue).
    private func flushPendingTexts() async {
        while let next = pendingTexts.first {
            guard await client.sendText(next.text) else { return }
            pendingTexts.removeFirst()
            await perform(machine.handle(.userSentText))
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
        // Des messages attendent déjà : celui-ci passe après eux, pour garder l'ordre.
        if pendingTexts.isEmpty, await client.sendText(trimmed) {
            if replayingMessageID != nil { stopReplay() }
            await perform(machine.handle(.userSentText))
        } else {
            // Hors connexion : rien n'est perdu ; le message est montré « en attente » et part au retour du réseau.
            pendingTexts.append(PendingText(id: UUID(), text: trimmed))
        }
    }

    public func setLanguage(_ language: AVELanguage) async {
        selectedLanguage = language
        await client.setLanguage(language)
        evaluateLearningPrompt()
    }

    // MARK: Apprentissage avec consentement

    /// Réponse de l'utilisateur à la notice affichée. Rien n'est coché d'avance ; un refus est mémorisé (pas de relance pour cette version).
    public func answerLearning(granted: Bool) async {
        guard let prompt = learningPrompt else { return }
        // Si le message ne part pas (hors ligne), la notice reste affichée : on ne perd pas la réponse en silence.
        guard await client.sendLearningConsent(granted: granted, version: prompt.version) else {
            notice = UserMessages.notConnected
            return
        }
        if !granted { learningPreferences.declinedVersion = prompt.version }
        learningPrompt = nil
    }

    /// Ferme la notice sans répondre (retour arrière) : rien n'est envoyé, et on ne redemande pas pendant cette session.
    public func dismissLearningPrompt() { learningPrompt = nil }

    /// Rouvre la notice à la demande de l'utilisateur (réglages), même après un refus.
    public func presentLearningPrompt() {
        guard learningOfferedToUser, let status = learning, status.available, !status.enabled,
              let text = LearningNotice.text(version: status.noticeVersion, language: selectedLanguage, in: configuration.learningNotices)
        else { return }
        learningPrompt = LearningPrompt(notice: text)
    }

    /// « Retirer mon aide » : retire le consentement ET efface côté serveur ce qui a été gardé.
    public func revokeLearning() async {
        guard await client.revokeLearning() else {
            notice = UserMessages.notConnected
            return
        }
        // Retirer son aide vaut refus de cette version : on ne la redemande pas.
        if let version = learning?.noticeVersion { learningPreferences.declinedVersion = version }
    }

    public var canGiveFeedback: Bool { learning?.enabled == true }

    /// 👍/👎 sur une réponse (correction facultative ≤ 1000 caractères). Seulement si l'utilisateur a consenti.
    public func sendFeedback(messageID: Int, rating: FeedbackRating, correction: String? = nil) async {
        guard canGiveFeedback, !feedbackGiven.contains(messageID),
              let utteranceID = transcript.message(messageID)?.utteranceID else { return }
        if (correction ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count > 1000 {
            notice = UserMessages.feedbackTooLong
            return
        }
        if await client.sendFeedback(utteranceID: utteranceID, rating: rating, correction: correction) {
            feedbackGiven.insert(messageID)
        } else {
            notice = UserMessages.notConnected
        }
    }

    public func dismissLearningMessage() { learningMessage = nil }

    /// Montre la notice à un moment calme : session ouverte, au repos, après le premier tour terminé, une seule fois par session.
    private func evaluateLearningPrompt() {
        guard learningOfferedToUser, learningPrompt == nil, phase == .idle, completedTurns >= configuration.learningPromptAfterTurns,
              LearningConsent.shouldAsk(status: learning, language: selectedLanguage,
                                        declinedVersion: learningPreferences.declinedVersion,
                                        askedThisSession: askedLearningThisSession,
                                        notices: configuration.learningNotices),
              let status = learning,
              let text = LearningNotice.text(version: status.noticeVersion, language: selectedLanguage, in: configuration.learningNotices)
        else { return }
        askedLearningThisSession = true
        learningPrompt = LearningPrompt(notice: text)
    }

    public func confirmAction(messageID: Int) {
        if let card = transcript.resolveCard(messageID: messageID, confirmed: true) { onAction?(card) }
    }

    public func declineAction(messageID: Int) {
        transcript.resolveCard(messageID: messageID, confirmed: false)
    }

    public func dismissNotice() { notice = nil }

    /// Rejoue l'audio mis en cache d'une réponse.
    public func replay(messageID: Int) {
        guard phase == .idle || phase == .listening, replayingMessageID == nil,
              let entry = replayCache.first(where: { $0.id == messageID }) else { return }
        replayingMessageID = messageID
        for chunk in entry.chunks { devices.player.enqueue(chunk) }
        devices.player.endOfUtterance()
        clearReplayWhenDrained(messageID)
    }

    public func hasCachedAudio(for messageID: Int) -> Bool {
        replayCache.contains { $0.id == messageID }
    }

    /// Limite du moteur pour `speak` (E7, `docs/ALIGNEMENT-IOS.md`).
    public static let speakMaxCharacters = 1000

    /// Vrai si « Lire à voix haute » peut marcher : audio gardé, ou réponse écrite assez courte pour `speak`.
    public func canReadAloud(messageID: Int) -> Bool {
        if hasCachedAudio(for: messageID) { return true }
        guard let message = transcript.message(messageID), message.role == .assistant, message.card == nil,
              !message.isVoiceOnly else { return false }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.count <= Self.speakMaxCharacters
    }

    /// « Lire à voix haute » : rejoue l'audio gardé s'il existe, sinon le demande au moteur (`speak`, E7 : synthèse seule,
    /// sans passer par le dialogue). La réponse du moteur ne crée PAS de nouvelle bulle ; son audio est gardé pour la fois
    /// suivante.
    public func readAloud(messageID: Int) async {
        if hasCachedAudio(for: messageID) {
            replay(messageID: messageID)
            return
        }
        guard canReadAloud(messageID: messageID), phase == .idle || phase == .listening, replayingMessageID == nil,
              speakingFor == nil, let message = transcript.message(messageID) else { return }
        speakingFor = messageID
        replayingMessageID = messageID
        if !(await client.speak(message.text)) {
            speakingFor = nil
            replayingMessageID = nil
            notice = UserMessages.notConnected
        }
    }

    /// Attend la fin de la lecture locale (sondage court, borné à 2 minutes) avant de rendre le bouton.
    private func clearReplayWhenDrained(_ messageID: Int) {
        Task { [weak self] in
            for _ in 0..<1_200 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.replayingMessageID == messageID else { return }
                if self.devices.player.isDrained { break }
            }
            if self?.replayingMessageID == messageID { self?.replayingMessageID = nil }
        }
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
        guard mode == .voice, micRunning, learningPrompt == nil else { return }
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
                await flushPendingTexts()
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
            learning = ready.learning
            learningPrompt = nil  // une nouvelle session recalcule la situation
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
            // Lecture à voix haute demandée (`speak`) : pas de nouvelle bulle, c'est la voix d'une réponse déjà affichée.
            if speakingFor == nil { transcript.apply(event) }
        case .ttsEnd(_, let interrupted):
            let id = speakingFor ?? transcript.currentAssistantID
            await perform(machine.handle(.ttsEnded(interrupted: interrupted)))
            if speakingFor == nil { transcript.apply(event) }
            if !interrupted {
                devices.player.endOfUtterance()
                if let id { cache(chunks: utteranceChunks, for: id) }
            }
            utteranceChunks = []
        case .turnEnd(_, let interrupted):
            await perform(machine.handle(.turnEnded(interrupted: interrupted)))
            // Le moteur clôt toujours un `speak` par `turn_end` : fin de la lecture demandée, rien à ajouter au fil.
            if let id = speakingFor {
                speakingFor = nil
                clearReplayWhenDrained(id)
                return
            }
            transcript.apply(event)
            if !interrupted { completedTurns += 1 }
        case .interrupted:
            await perform(machine.handle(.serverInterrupted))
            transcript.apply(event)
        case .turnError:
            await perform(machine.handle(.turnFailed))
            transcript.apply(event)
        case .learningState(let enabled, let reason, let deleted, let noticeVersion):
            if let current = learning {
                learning = LearningStatus(available: current.available && reason != "not_available", enabled: enabled,
                                          noticeVersion: noticeVersion ?? current.noticeVersion)
            }
            switch reason {
            case "granted": learningMessage = UserMessages.learningThanks
            case "revoked": learningMessage = UserMessages.learningRevoked(deleted: deleted)
            case "stale_notice":
                // Notice périmée : on ne montre une nouvelle demande que si on possède le texte EXACT de la nouvelle version.
                askedLearningThisSession = false
                learningPrompt = nil
            default: break
            }
        case .feedbackAck(let stored):
            if stored { learningMessage = UserMessages.feedbackThanks }
        case .taskStarted, .taskDone, .taskError:
            handleTask(event)
        case .action, .replyText, .transcript:
            if let auto = transcript.apply(event), let card = auto.card { onAction?(card) }
        default:
            break
        }
    }

    private func handleAudio(_ data: Data) {
        guard machine.acceptsTTSAudio else { return }  // reliquat d'un énoncé annulé
        utteranceChunks.append(data)  // gardé dans tous les cas : « Lire à voix haute » le rejouera
        if mode == .voice || autoPlayInTextMode || speakingFor != nil { devices.player.enqueue(data) }
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
            if shouldResume, (try? devices.lifecycle.activate()) != nil, mode == .voice, !micMuted { await startMic() }
        case .routeChanged(_, let reason):
            if reason == .oldDeviceUnavailable { await interruptAssistant() }
        case .mediaServicesReset:
            stopMic()
            if (try? devices.lifecycle.activate()) != nil, mode == .voice, !micMuted { await startMic() }
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
        evaluateLearningPrompt()
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
