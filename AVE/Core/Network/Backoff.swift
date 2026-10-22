import Foundation

/// Délais de reconnexion : 250 ms, 500 ms, 1 s, 2 s, 4 s, puis plafonnés à 5 s.
public struct Backoff: Sendable, Equatable {
    public var initial: Duration
    public var maximum: Duration

    public init(initial: Duration = .milliseconds(250), maximum: Duration = .seconds(5)) {
        self.initial = initial
        self.maximum = maximum
    }

    /// `attempt` commence à 0 (premier nouvel essai).
    public func delay(forAttempt attempt: Int) -> Duration {
        var d = initial
        var i = 0
        while i < attempt && d < maximum {
            d = d * 2
            i += 1
        }
        return min(d, maximum)
    }
}
