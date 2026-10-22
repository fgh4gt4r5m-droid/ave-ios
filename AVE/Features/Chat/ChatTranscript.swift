import AVECore

/// Intention d'action reçue du serveur (`tool_call`), à exécuter par l'application hôte.
public struct ActionCard: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case awaitingConfirmation
        case confirmed
        case declined
    }

    public let name: String
    public let args: [String: JSONValue]
    public var status: Status

    /// DÉCISION DE SÉCURITÉ : la confirmation est exigée sauf si le serveur dit explicitement
    /// `confirm: false`. Le serveur du sprint 1 n'envoie pas ce champ (contrat E5/Q1) ; exécuter
    /// sans accord une action comme `order_ride` serait dangereux.
    public static func requiresConfirmation(args: [String: JSONValue]) -> Bool {
        args["confirm"]?.boolValue != false
    }

    /// Résumé lisible des arguments (sans le champ technique `confirm`).
    public var summary: String {
        args.filter { $0.key != "confirm" }
            .sorted { $0.key < $1.key }
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
    /// Réponse parlée dont le texte est inconnu (pas de `reply_text`) : l'UI affiche « Réponse vocale ».
    public var isVoiceOnly: Bool
    public var card: ActionCard?
}

/// Construit la conversation à partir des événements serveur. Pure, testable.
public struct ChatTranscript: Sendable, Equatable {
    public private(set) var messages: [ChatMessage] = []
    /// Message assistant en cours de construction (phrase par phrase via `reply_text`).
    public private(set) var currentAssistantID: Int?
    private var nextID = 1

    public init() {}

    public mutating func appendUserText(_ text: String) {
        append(role: .user, text: text, status: .complete)
        currentAssistantID = nil
    }

    public mutating func appendSystem(_ text: String) {
        append(role: .system, text: text, status: .complete)
    }

    /// Renvoie le message portant une carte d'action à exécuter immédiatement (`confirm: false`).
    @discardableResult
    public mutating func apply(_ event: ServerEvent) -> ChatMessage? {
        switch event {
        case .transcript(let text, _, _):
            append(role: .user, text: text, status: .complete)
            currentAssistantID = nil

        case .replyText(let text):
            if let id = currentAssistantID, let i = index(of: id) {
                if messages[i].isVoiceOnly {
                    messages[i].text = text
                    messages[i].isVoiceOnly = false
                } else {
                    messages[i].text += " " + text
                }
            } else {
                currentAssistantID = append(role: .assistant, text: text, status: .streaming)
            }

        case .ttsStart:
            if currentAssistantID == nil {
                currentAssistantID = append(role: .assistant, text: "", status: .streaming, voiceOnly: true)
            }

        case .ttsEnd(_, let interrupted):
            finishAssistant(interrupted ? .interrupted : .complete)

        case .interrupted:
            finishAssistant(.interrupted)

        case .turnError(let code, _):
            finishAssistant(.interrupted)
            appendSystem(UserMessages.turnError(code: code))

        case .toolCall(let name, let args):
            let needsConfirmation = ActionCard.requiresConfirmation(args: args)
            let card = ActionCard(name: name, args: args, status: needsConfirmation ? .awaitingConfirmation : .confirmed)
            let id = append(role: .assistant, text: "", status: .complete, card: card)
            return needsConfirmation ? nil : message(id)

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

    // MARK: Interne

    private func index(of id: Int) -> Int? { messages.firstIndex { $0.id == id } }

    private mutating func finishAssistant(_ status: ChatMessage.Status) {
        if let id = currentAssistantID, let i = index(of: id) { messages[i].status = status }
        currentAssistantID = nil
    }

    @discardableResult
    private mutating func append(role: ChatMessage.Role, text: String, status: ChatMessage.Status,
                                 voiceOnly: Bool = false, card: ActionCard? = nil) -> Int {
        let id = nextID
        nextID += 1
        messages.append(ChatMessage(id: id, role: role, text: text, status: status, isVoiceOnly: voiceOnly, card: card))
        return id
    }
}
