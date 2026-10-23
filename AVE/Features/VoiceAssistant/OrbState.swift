import AVECore

/// État affiché par l'orbe vocal. Pur : mappe phase du tour + connexion, sans dépendre de SwiftUI.
public enum OrbState: Sendable, Equatable {
    case idle, listening, thinking, speaking, interrupted, reconnecting, unavailable

    public init(phase: BargeInStateMachine.Phase, connection: ConnectionState) {
        switch connection {
        case .idle, .connecting, .reconnecting:
            self = .reconnecting
        case .failed, .closed:
            self = .unavailable
        case .open:
            switch phase {
            case .idle: self = .idle
            case .listening: self = .listening
            case .thinking: self = .thinking
            case .speaking: self = .speaking
            case .interrupted: self = .interrupted
            }
        }
    }

    /// Libellé lu par VoiceOver (l'état ne doit pas passer par la seule couleur).
    public var label: String {
        switch self {
        case .idle: return "Prêt"
        case .listening: return "À l'écoute"
        case .thinking: return "Réflexion en cours"
        case .speaking: return "L'assistant parle"
        case .interrupted: return "Interrompu"
        case .reconnecting: return "Connexion en cours"
        case .unavailable: return "Indisponible"
        }
    }

    public var hint: String {
        switch self {
        case .speaking: return "Touchez deux fois pour interrompre l'assistant."
        case .listening, .idle: return "Parlez, l'assistant vous écoute."
        case .thinking: return "Patientez, la réponse arrive."
        case .interrupted: return "Vous avez interrompu l'assistant."
        case .reconnecting: return "La connexion est en cours de rétablissement."
        case .unavailable: return "La session est terminée."
        }
    }

    /// Légende VISIBLE sous l'orbe. Distincte de `hint`, qui est lu par VoiceOver (« Touchez deux fois… » n'a de sens
    /// que pour lui).
    public var caption: String {
        switch self {
        case .speaking: return "Parlez ou touchez l'orbe pour l'interrompre."
        default: return hint
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
        case .unavailable: return "wifi.slash"
        }
    }

    /// L'amplitude de l'orbe suit le niveau audio (micro ou lecture) dans ces états.
    public var followsLevel: Bool { self == .listening || self == .speaking }

    /// Seul l'état « parle » répond au toucher (interrompre).
    public var isInteractive: Bool { self == .speaking }
}
