import AVECore
import Foundation

/// Intention d'action reçue du serveur (`action`), à exécuter par l'application hôte.
public struct ActionCard: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case awaitingConfirmation
        case confirmed
        case declined
    }

    public let name: String
    public let args: [String: JSONValue]
    /// `true` : accord explicite de l'utilisateur requis avant d'exécuter (argent, annulation). La voix seule ne suffit pas.
    public let requiresConfirmation: Bool
    public var status: Status

    /// Résumé lisible des arguments (chaînes uniquement).
    public var summary: String {
        args.sorted { $0.key < $1.key }
            .compactMap { key, value in value.stringValue.map { "\(key) : \($0)" } }
            .joined(separator: "\n")
    }
}

public struct ChatMessage: Identifiable, Sendable, Equatable {
    public enum Role: Sendable, Equatable { case user, assistant, system }
    public enum Status: Sendable, Equatable { case streaming, complete, interrupted }

    public let id: Int
    public let role: Role
    public var text: String
    public var status: Status
    /// Tour du serveur auquel appartient ce message assistant (`utterance_id`).
    public let utteranceID: Int?
    /// Réponse parlée dont le texte est inconnu (pas de `reply_text`) : l'UI affiche « Réponse vocale ».
    public var isVoiceOnly: Bool
    public var card: ActionCard?
    /// Photo ou document joint, image ou document produit (gardé sur l'iPhone).
    public var media: MediaItem?
    /// Tâche en cours ou échouée ; remplacée par `media` quand le résultat est téléchargé.
    public var task: MediaTaskCard?
}

/// Construit la conversation à partir des événements serveur. Pure, testable.
/// La bulle utilisateur vient de l'écho `transcript` (voix ET texte) : l'app n'en fabrique pas d'autre.
public struct ChatTranscript: Sendable, Equatable {
    public private(set) var messages: [ChatMessage] = []
    /// Message assistant en cours de construction (phrase par phrase via `reply_text`).
    public private(set) var currentAssistantID: Int?
    private var nextID = 1
    /// Tours dont la réponse arrive en fragments (D7) : leurs `reply_text` ne servent plus qu'à la voix.
    private var deltaUtterances: Set<Int> = []

    public init() {}

    /// Fil rouvert depuis l'historique : messages terminés, sans `utterance_id` (ils n'appartiennent à aucune session du
    /// moteur : pas d'avis 👍/👎 possible dessus), suivis d'un message système qui dit que l'assistant repart sans mémoire.
    public init(restoring stored: [StoredMessage], notice: String? = nil) {
        for message in stored {
            let role: ChatMessage.Role
            switch message.role {
            case .user: role = .user
            case .assistant: role = .assistant
            case .system: role = .system
            }
            append(role: role, text: message.text, status: message.interrupted ? .interrupted : .complete,
                   voiceOnly: message.voiceOnly, media: message.media.map(MediaItem.init(restoring:)))
        }
        if let notice, !stored.isEmpty { appendSystem(notice) }
    }

    public mutating func appendSystem(_ text: String) {
        append(role: .system, text: text, status: .complete)
    }

    /// Renvoie le message portant une carte d'action à exécuter immédiatement (`confirm: false`).
    @discardableResult
    public mutating func apply(_ event: ServerEvent) -> ChatMessage? {
        switch event {
        case .transcript(let text, _, _, _, _):
            // Un seul transcript par tour, toujours final (`speculative` = calculé d'avance, pas provisoire).
            append(role: .user, text: text, status: .complete)
            currentAssistantID = nil

        case .replyText(let utteranceID, let text, _):
            // Fragments déjà affichés pour ce tour : ils couvrent ce `reply_text` (jamais les deux, D7).
            guard !deltaUtterances.contains(utteranceID) else { break }
            appendReply(text, utteranceID: utteranceID)

        case .replyDelta(let utteranceID, let text):
            deltaUtterances.insert(utteranceID)
            appendReply(text, utteranceID: utteranceID)

        case .ttsStart(let utteranceID, _, _):
            if currentIndex(utterance: utteranceID) == nil {
                currentAssistantID = append(role: .assistant, text: "", status: .streaming,
                                            utteranceID: utteranceID, voiceOnly: true)
            }

        case .ttsEnd(_, true):
            // Le moteur annonce la coupure par `tts_end {interrupted:true}` AVANT `interrupted` (PROTOCOL.md, barge-in) :
            // la bulle est marquée dès ce premier signal, sans dépendre de l'arrivée des suivants (réseau instable).
            // Un `tts_end` normal ne clôt rien : d'autres phrases du même tour peuvent suivre.
            finishAssistant(.interrupted)

        case .turnEnd(_, let interrupted):
            finishAssistant(interrupted ? .interrupted : .complete)

        case .interrupted:
            finishAssistant(.interrupted)

        case .turnError(let code, _, _, let retryAfter):
            finishAssistant(.interrupted)
            appendSystem(UserMessages.turnError(code: code, retryAfterSeconds: retryAfter))

        case .action(let name, let args, let confirm):
            let card = ActionCard(name: name, args: args, requiresConfirmation: confirm,
                                  status: confirm ? .awaitingConfirmation : .confirmed)
            let id = append(role: .assistant, text: "", status: .complete, card: card)
            return confirm ? nil : message(id)

        default:
            break
        }
        return nil
    }

    /// Met à jour la carte d'un message. Renvoie la carte si elle vient d'être confirmée.
    @discardableResult
    public mutating func resolveCard(messageID: Int, confirmed: Bool) -> ActionCard? {
        guard let i = index(of: messageID), var card = messages[i].card,
              card.status == .awaitingConfirmation else { return nil }
        card.status = confirmed ? .confirmed : .declined
        messages[i].card = card
        return confirmed ? card : nil
    }

    public func message(_ id: Int) -> ChatMessage? {
        index(of: id).map { messages[$0] }
    }

    // MARK: Fichiers et images (E16)

    /// La demande de la personne, telle qu'elle la voit (« Traduire en anglais », la description d'une image). Ces demandes
    /// ne passent pas par `text` : le moteur n'en renvoie pas d'écho `transcript`, la bulle est donc créée ici.
    @discardableResult
    public mutating func appendUserRequest(_ text: String) -> Int {
        append(role: .user, text: text, status: .complete)
    }

    @discardableResult
    public mutating func appendAttachment(_ media: MediaItem) -> Int {
        append(role: .user, text: "", status: .complete, media: media)
    }

    @discardableResult
    public mutating func appendTask(_ card: MediaTaskCard) -> Int {
        append(role: .assistant, text: "", status: .complete, task: card)
    }

    public mutating func updateMedia(messageID: Int, _ change: (inout MediaItem) -> Void) {
        guard let i = index(of: messageID), var media = messages[i].media else { return }
        change(&media)
        messages[i].media = media
    }

    public mutating func updateTask(messageID: Int, _ change: (inout MediaTaskCard) -> Void) {
        guard let i = index(of: messageID), var task = messages[i].task else { return }
        change(&task)
        messages[i].task = task
    }

    /// Le résultat est sur l'iPhone : la carte de tâche devient l'image ou le document.
    public mutating func completeTask(messageID: Int, with media: MediaItem) {
        guard let i = index(of: messageID) else { return }
        messages[i].task = nil
        messages[i].media = media
    }

    public func messageID(forTaskRef ref: String) -> Int? {
        messages.first { $0.task?.ref == ref }?.id
    }

    /// Applique un événement `task_*` à la carte qui porte son `ref`. Renvoie le résultat à télécharger (`task_done`).
    /// Sans effet sur une carte déjà terminée : à la reprise de session, le moteur rejoue ses événements numérotés.
    @discardableResult
    public mutating func applyTask(_ event: ServerEvent, now: Date = Date()) -> (messageID: Int, result: MediaTaskResult)? {
        switch event {
        case .taskStarted(let started):
            if messageID(forTaskRef: started.ref) == nil {
                // D12 : image lancée par le moteur pendant le tour (« fais-moi une image de… ») : une carte à elle. Un
                // `task_started` rejoué (reprise de session) ne la double pas, même après son résultat.
                guard started.ref.hasPrefix(MediaTaskCard.chatRefPrefix), started.kind == .imageGenerate,
                      !messages.contains(where: { $0.task?.taskID == started.taskID || $0.media?.taskID == started.taskID })
                else { return nil }
                appendTask(MediaTaskCard(ref: started.ref,
                                         request: .imageGenerate(prompt: started.prompt ?? "", size: started.size,
                                                                 quality: started.quality, ref: started.ref),
                                         resultTitle: "Image", taskID: started.taskID,
                                         state: .working(startedAt: now, estimatedSeconds: started.estimatedSeconds)))
                return nil
            }
            guard let id = messageID(forTaskRef: started.ref), let task = message(id)?.task, task.canCancel else { return nil }
            updateTask(messageID: id) {
                $0.taskID = started.taskID
                if case .working = $0.state { return }
                $0.state = .working(startedAt: now, estimatedSeconds: started.estimatedSeconds)
            }
        case .taskDone(let result):
            guard let id = messageID(forTaskRef: result.ref), let task = message(id)?.task, !task.isFinished else { return nil }
            if task.state == .downloading, task.pendingResult == result { return nil }  // rejeu
            updateTask(messageID: id) {
                $0.taskID = result.taskID
                $0.state = .downloading
                $0.pendingResult = result
            }
            return (id, result)
        case .taskError(let failure):
            guard let id = messageID(forTaskRef: failure.ref), let task = message(id)?.task, !task.isFinished else { return nil }
            updateTask(messageID: id) {
                if let taskID = failure.taskID { $0.taskID = taskID }
                $0.state = failure.code == "cancelled"
                    ? .cancelled : .failed(code: failure.code, retryAfterSeconds: failure.retryAfterSeconds)
            }
        default:
            break
        }
        return nil
    }

    /// Noms des fichiers gardés sur l'iPhone par ce fil (pour ne pas les effacer).
    public var mediaNames: Set<String> {
        Set(messages.compactMap { $0.media?.localName })
    }

    // MARK: Interne

    private func index(of id: Int) -> Int? { messages.firstIndex { $0.id == id } }

    private func currentIndex(utterance: Int) -> Int? {
        guard let id = currentAssistantID, let i = index(of: id), messages[i].utteranceID == utterance else { return nil }
        return i
    }

    /// Texte EXACT (D7) : le moteur fournit les espaces et les retours à la ligne ; concaténer sans rien ajouter garde
    /// intacts les listes, titres et tableaux.
    private mutating func appendReply(_ text: String, utteranceID: Int) {
        if let i = currentIndex(utterance: utteranceID) {
            if messages[i].isVoiceOnly {
                messages[i].text = text
                messages[i].isVoiceOnly = false
            } else {
                messages[i].text += text
            }
        } else {
            let id = append(role: .assistant, text: text, status: .streaming, utteranceID: utteranceID)
            // D12 : la carte d'une image lancée pendant ce tour peut arriver avant la phrase qui l'annonce
            // (« Je m'occupe de te créer cette image. ») ; la phrase passe devant, comme dans une réponse lue.
            let last = messages.count - 1
            if last > 0, messages[last - 1].task?.ref == MediaTaskCard.chatRefPrefix + String(utteranceID) {
                messages.swapAt(last, last - 1)
            }
            currentAssistantID = id
        }
    }

    private mutating func finishAssistant(_ status: ChatMessage.Status) {
        if let id = currentAssistantID, let i = index(of: id) { messages[i].status = status }
        currentAssistantID = nil
    }

    @discardableResult
    private mutating func append(role: ChatMessage.Role, text: String, status: ChatMessage.Status,
                                 utteranceID: Int? = nil, voiceOnly: Bool = false, card: ActionCard? = nil,
                                 media: MediaItem? = nil, task: MediaTaskCard? = nil) -> Int {
        let id = nextID
        nextID += 1
        messages.append(ChatMessage(id: id, role: role, text: text, status: status, utteranceID: utteranceID,
                                    isVoiceOnly: voiceOnly, card: card, media: media, task: task))
        return id
    }
}
