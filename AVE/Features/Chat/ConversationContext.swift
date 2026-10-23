import AVECore

/// Ce que le moteur reçoit d'une conversation au début d'une session neuve (D9) : les échanges lisibles, aux bornes du
/// moteur, pour que l'assistant reprenne là où on s'était arrêté. Pur, testé.
public enum ConversationContext {
    /// Messages de la personne et de l'assistant qui ont du texte (pas les avis de l'app, les cartes d'action, les
    /// pièces jointes sans texte ni les réponses seulement vocales). Une réponse interrompue compte : le moteur garde
    /// aussi la partie déjà dite. Chaque texte est coupé à 4000 caractères ; on garde les 20 plus récents, puis on
    /// retire les plus anciens jusqu'à 8000 caractères en tout (le moteur ferait de même, mais un texte trop long
    /// fermerait la session : `bad_context`).
    public static func messages(from transcript: [ChatMessage]) -> [ContextMessage] {
        let candidates: [ContextMessage] = transcript.compactMap { message in
            guard message.card == nil, message.task == nil, !message.isVoiceOnly else { return nil }
            let role: ContextMessage.Role
            switch message.role {
            case .user: role = .user
            case .assistant: role = .assistant
            case .system: return nil
            }
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return ContextMessage(role: role, text: String(text.prefix(ContextMessage.maxTextCharacters)))
        }
        var kept = Array(candidates.suffix(ContextMessage.maxMessages))
        while kept.reduce(0, { $0 + $1.text.count }) > ContextMessage.maxTotalCharacters, !kept.isEmpty {
            kept.removeFirst()
        }
        return kept
    }
}
