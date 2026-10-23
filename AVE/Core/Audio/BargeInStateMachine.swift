/// Machine d'états du tour de parole côté client. Pure : aucune dépendance audio ni réseau,
/// donc testable sans matériel. Elle décide quoi faire (`Action`), le coordinateur l'exécute.
///
/// Chemin du barge-in : l'utilisateur parle pendant que l'assistant parle → on purge la lecture
/// IMMÉDIATEMENT (localement, sans attendre le serveur) et on envoie `interrupt`.
public struct BargeInStateMachine: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle         // au repos
        case listening    // l'utilisateur parle
        case thinking     // end_of_speech envoyé, réponse attendue
        case speaking     // l'assistant parle
        case interrupted  // barge-in local, confirmation serveur attendue
    }

    public enum Input: Sendable, Equatable {
        case userSpeechStarted
        case userSpeechEnded
        case ttsStarted
        case ttsEnded(interrupted: Bool)
        case serverInterrupted
        /// `turn_error` ou délai dépassé : le tour est perdu.
        case turnFailed
        /// Connexion perdue ou session arrêtée.
        case sessionLost
        /// `turn_end` reçu : clôt un tour, y compris sans audio (mode texte).
        case turnEnded(interrupted: Bool)
        /// L'utilisateur a envoyé un message texte (le serveur le traite comme un barge-in si besoin).
        case userSentText
        /// Coupure volontaire (bouton, passage en mode texte, appel entrant) : l'utilisateur ne parle pas.
        case manualInterrupt
    }

    public enum Action: Sendable, Equatable {
        case purgePlayback
        case sendInterrupt
        case sendEndOfSpeech
    }

    public private(set) var phase: Phase = .idle

    public init() {}

    /// L'audio TTS reçu n'est joué que pendant `speaking`. Tout le reste est du reliquat d'un
    /// énoncé annulé (le serveur envoie tout l'ancien audio avant `tts_end(interrupted)`).
    public var acceptsTTSAudio: Bool { phase == .speaking }

    public mutating func handle(_ input: Input) -> [Action] {
        switch (phase, input) {
        case (.idle, .userSpeechStarted):
            phase = .listening
        case (.idle, .ttsStarted):  // réponse à la demande (lecture sans question préalable)
            phase = .speaking

        // Texte envoyé : on attend la réponse. Si l'assistant parlait, on purge localement
        // (le serveur interrompt de lui-même sur `text` : pas de `interrupt` à envoyer).
        case (.speaking, .userSentText):
            phase = .thinking
            return [.purgePlayback]
        case (_, .userSentText):
            phase = .thinking

        case (.listening, .userSpeechEnded):
            phase = .thinking
            return [.sendEndOfSpeech]

        case (.thinking, .ttsStarted):
            phase = .speaking
        case (.thinking, .userSpeechStarted):  // l'utilisateur reprend : la nouvelle phrase remplace la réponse
            phase = .listening
        case (.thinking, .turnFailed):
            phase = .idle
        // « Arrêter » pendant que le moteur prépare sa réponse (aucun audio encore) : rien à purger, on le prévient.
        case (.thinking, .manualInterrupt):
            phase = .idle
            return [.sendInterrupt]
        // Fin de tour sans audio (réponse texte) ou réponse vide. Un `turn_end(interrupted:true)` en
        // réflexion est le reliquat du tour que l'utilisateur vient de couper : ignoré.
        case (.thinking, .turnEnded(let interrupted)):
            if !interrupted { phase = .idle }

        case (.speaking, .userSpeechStarted):  // BARGE-IN
            phase = .interrupted
            return [.purgePlayback, .sendInterrupt]
        case (.speaking, .ttsEnded(let interrupted)):
            phase = .idle
            return interrupted ? [.purgePlayback] : []  // interruption décidée par le serveur
        case (.speaking, .serverInterrupted):
            phase = .idle
            return [.purgePlayback]
        case (.speaking, .manualInterrupt):
            phase = .idle
            return [.purgePlayback, .sendInterrupt]
        case (.speaking, .turnEnded):  // `tts_end` manqué : on ne bloque pas l'état
            phase = .idle
        case (.speaking, .turnFailed):
            phase = .idle
            return [.purgePlayback]

        case (.interrupted, .ttsEnded), (.interrupted, .serverInterrupted):
            phase = .listening  // l'utilisateur est en train de parler
        case (.interrupted, .userSpeechEnded):  // il a fini avant la confirmation serveur
            phase = .thinking
            return [.sendEndOfSpeech]
        case (.interrupted, .turnFailed):
            phase = .idle

        case (.speaking, .sessionLost):
            phase = .idle
            return [.purgePlayback]
        case (_, .sessionLost):
            phase = .idle

        default:
            break  // reliquats tardifs (ex. ttsEnded(interrupted) reçu en .thinking) : ignorés
        }
        return []
    }
}
