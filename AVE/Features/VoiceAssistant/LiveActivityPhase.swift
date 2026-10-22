/// État affiché dans la Dynamic Island et sur l'écran verrouillé. Volontairement minimal :
/// AUCUN texte de la conversation (visible sans déverrouiller l'iPhone).
/// Fichier autonome (aucune dépendance) : il est compilé AUSSI dans l'extension Live Activity, qui ne lie pas AVEKit
/// (voir `project.yml`). Ce qui dépend du reste d'AVEKit vit dans `SessionActivityPresenting.swift`.
public enum LiveActivityPhase: String, Sendable, Codable, Hashable {
    case idle, listening, thinking, speaking, interrupted, reconnecting

    public var label: String {
        switch self {
        case .idle: return "Prêt"
        case .listening: return "À l'écoute"
        case .thinking: return "Réflexion"
        case .speaking: return "L'assistant parle"
        case .interrupted: return "Interrompu"
        case .reconnecting: return "Reconnexion"
        }
    }

    public var symbolName: String {
        switch self {
        case .idle: return "mic.fill"
        case .listening: return "waveform"
        case .thinking: return "ellipsis"
        case .speaking: return "speaker.wave.2.fill"
        case .interrupted: return "hand.raised.fill"
        case .reconnecting: return "wifi.exclamationmark"
        }
    }
}
