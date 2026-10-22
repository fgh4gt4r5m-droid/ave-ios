#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

/// Attributs de la Live Activity. Ce fichier est compilé dans AVEKit (côté app) ET directement dans l'extension
/// Widget, qui ne lie pas AVEKit : c'est le modèle d'Apple (ActivityKit associe les deux par le nom du type).
/// Lier le même package depuis l'app et l'extension par des produits différents fait échouer Xcode.
/// `Sendable` explicite : les types publics ne l'obtiennent pas implicitement et ActivityKit transmet ces valeurs.
public struct AVESessionAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var phaseRaw: String
        public init(phaseRaw: String) { self.phaseRaw = phaseRaw }
    }

    /// Début de session, pour le chronomètre. Aucune donnée personnelle.
    public var startedAt: Date
    public init(startedAt: Date) { self.startedAt = startedAt }
}
#endif
