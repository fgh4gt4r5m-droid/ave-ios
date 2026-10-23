import CoreGraphics
import Foundation

/// Le mot « AVE » (maquette validée le 2026-10-23), redessiné en vecteur d'après le fichier du propriétaire (1024 px) :
/// l'arche du A, le V, le point ambre, les trois barres du E. Les mesures restent en pixels du fichier pour pouvoir les
/// recontrôler sur l'image (dossier « DOSSIER AVE » du bureau, `logos/sources/mot-AVE-1024.png`). Pur, testé.
public enum AVEWordmarkGeometry {
    /// Boîte du dessin (traits compris), pixels du fichier : sert au cadrage et au centrage.
    public static let bounds = CGRect(x: 133, y: 375, width: 760, height: 214)
    public static let stroke: CGFloat = 48

    /// Le A : une arche (deux jambes droites et un sommet arrondi), tracée de la jambe gauche à la jambe droite.
    public static let aStart = CGPoint(x: 157, y: 564)
    public static let aLeftShoulder = CGPoint(x: 212.8, y: 462)
    public static let aApexControl = CGPoint(x: 273, y: 352)
    public static let aRightShoulder = CGPoint(x: 333.2, y: 462)
    public static let aEnd = CGPoint(x: 389, y: 564)
    /// Le V, tracé de gauche à droite.
    public static let vPoints = [CGPoint(x: 404, y: 400), CGPoint(x: 505, y: 562), CGPoint(x: 605, y: 400)]
    /// Le point ambre, sous le sommet du A.
    public static let dotCenter = CGPoint(x: 273, y: 506.5)
    public static let dotRadius: CGFloat = 22
    /// Barres du E (haut, milieu plus courte, bas), hauteur commune.
    public static let bars = [CGRect(x: 666, y: 375, width: 227, height: 48),
                              CGRect(x: 666, y: 458, width: 185, height: 48),
                              CGRect(x: 666, y: 541, width: 227, height: 48)]

    // MARK: Animation d'entrée

    /// État de chaque élément à un instant donné (0 = rien, 1 = en place).
    public struct Frame: Sendable, Equatable {
        /// Part tracée du A et du V.
        public var aTrim: CGFloat
        public var vTrim: CGFloat
        /// Longueur de chaque barre du E (0 → 1), depuis la gauche.
        public var bars: [CGFloat]
        /// Hauteur restant à tomber pour le point (pixels du fichier) et son opacité.
        public var dotDrop: CGFloat
        public var dotOpacity: CGFloat
        /// Sous-titre : opacité et petite remontée (pixels du fichier).
        public var subtitleOpacity: CGFloat
        public var subtitleRise: CGFloat
    }

    /// Le mot en place, sans animation (« Réduire les animations », ou animation terminée).
    public static let still = Frame(aTrim: 1, vTrim: 1, bars: [1, 1, 1], dotDrop: 0, dotOpacity: 1,
                                    subtitleOpacity: 1, subtitleRise: 0)

    /// Durée totale de l'entrée.
    public static let duration: Double = 1.8

    /// Les lettres se tracent comme une onde (le A, puis le V), les barres du E s'allongent l'une après l'autre, le point
    /// tombe dans le A avec un petit rebond, puis le sous-titre apparaît en remontant légèrement.
    public static func frame(elapsed t: Double) -> Frame {
        let ease = AVEMarkGeometry.ease
        let dot = (t - 0.85) / 0.6
        let subtitle = ease((t - 1.2) / 0.6)
        return Frame(
            aTrim: CGFloat(ease(t / 0.7)),
            vTrim: CGFloat(ease((t - 0.2) / 0.7)),
            bars: bars.indices.map { CGFloat(ease((t - 0.45 - Double($0) * 0.12) / 0.5)) },
            dotDrop: CGFloat((1 - spring(dot)) * 140),
            dotOpacity: dot > 0 ? 1 : 0,
            subtitleOpacity: CGFloat(subtitle),
            subtitleRise: CGFloat(12 * (1 - subtitle)))
    }

    /// Rebond amorti, borné à 0…1 en entrée ; vaut 1 à la fin.
    static func spring(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return 1 - cos(t * Double.pi * 2.5) * exp(-5 * t)
    }
}
