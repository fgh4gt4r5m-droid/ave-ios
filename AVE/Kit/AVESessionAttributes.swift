#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

/// Attributs de la Live Activity. Partagés par l'app et l'extension Widget (les deux importent AVEKit).
public struct AVESessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var phaseRaw: String
        public init(phaseRaw: String) { self.phaseRaw = phaseRaw }
    }

    /// Début de session, pour le chronomètre. Aucune donnée personnelle.
    public var startedAt: Date
    public init(startedAt: Date) { self.startedAt = startedAt }
}
#endif
