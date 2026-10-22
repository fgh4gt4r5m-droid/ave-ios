extension LiveActivityPhase {
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
}

/// Port de présentation : le coordinateur ne connaît pas ActivityKit (testable avec un faux).
@MainActor
public protocol SessionActivityPresenting: AnyObject {
    func start()
    func update(_ phase: LiveActivityPhase)
    func end()
}
