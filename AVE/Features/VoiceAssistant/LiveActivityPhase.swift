/// État affiché dans la Dynamic Island et sur l'écran verrouillé. Volontairement minimal :
/// AUCUN texte de la conversation (visible sans déverrouiller l'iPhone).
public enum LiveActivityPhase: String, Sendable, Codable, Hashable {
    case idle, listening, thinking, speaking, interrupted, reconnecting

    /// `nil` quand la session est terminée ou perdue : la Live Activity doit alors être arrêtée.
    public init?(orb: OrbState) {
        switch orb {
        case .idle: self = .idle
        case .listening: self = .listening
        case .thinking: self = .thinking
        case .speaking: self = .speaking
        case .interrupted: self = .interrupted
        case .reconnecting: self = .reconnecting
        case .unavailable: return nil
        }
    }

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

/// Port de présentation : le coordinateur ne connaît pas ActivityKit (testable avec un faux).
@MainActor
public protocol SessionActivityPresenting: AnyObject {
    func start()
    func update(_ phase: LiveActivityPhase)
    func end()
}
