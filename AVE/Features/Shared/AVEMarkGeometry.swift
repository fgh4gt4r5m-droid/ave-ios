import CoreGraphics
import Foundation

/// Ce que montre le logo vivant (maquettes validées par le propriétaire le 2026-10-23).
/// - `idle` (repos, l'assistant attend un message) : l'Afrique DESSINÉE PAR LES BARRES, traversée par une ligne d'onde,
///   qui respire (dessin recalé sur les fichiers du propriétaire).
/// - les autres : l'Afrique en contour qui se transforme (cercle, onde, bulle) pendant que les sept barres pulsent.
public enum AVEMarkPhase: Sendable, Equatable {
    /// Naissance : un cercle devient l'Afrique, les barres montent une à une, puis le logo passe au repos.
    case launch
    case idle, listening, thinking, speaking

    /// Correspondance avec l'état de la session. La reconnexion, l'interruption et l'indisponibilité restent au repos :
    /// c'est le texte d'état qui les dit (le logo ne porte jamais seul une information).
    public init(orb: OrbState) {
        switch orb {
        case .listening: self = .listening
        case .thinking: self = .thinking
        case .speaking: self = .speaking
        case .idle, .interrupted, .reconnecting, .unavailable: self = .idle
        }
    }
}

/// Géométrie du logo, pure (sans SwiftUI) pour être testée. Repère : carré 0…100 ; la vue ajoute une marge de 10
/// de chaque côté pour la lueur. Le tracé est un relevé du logo généré (`ave-logo.png`), simplifié : un designer pourra
/// l'affiner sans toucher aux animations.
public enum AVEMarkGeometry {
    // MARK: Contour

    /// Toutes les formes ont le même nombre de points et partent du même endroit (le Maroc, en haut à gauche) dans le
    /// même sens : on passe de l'une à l'autre point par point, sans saut ni retournement.
    public static let pointCount = 96

    /// Silhouette relevée sur le logo (600 × 640 px ramenés à 0…100), sens horaire depuis le Maroc.
    static let africaTrace: [CGPoint] = [
        CGPoint(x: 10, y: 22), CGPoint(x: 20, y: 9), CGPoint(x: 32, y: 5), CGPoint(x: 42, y: 6), CGPoint(x: 50, y: 11),
        CGPoint(x: 60, y: 14), CGPoint(x: 70, y: 16), CGPoint(x: 73, y: 24), CGPoint(x: 79, y: 31), CGPoint(x: 93, y: 37),
        CGPoint(x: 87, y: 45), CGPoint(x: 78, y: 52), CGPoint(x: 73, y: 60), CGPoint(x: 70, y: 69), CGPoint(x: 66, y: 79),
        CGPoint(x: 57, y: 92), CGPoint(x: 50, y: 97), CGPoint(x: 42, y: 90), CGPoint(x: 39, y: 76), CGPoint(x: 40, y: 62),
        CGPoint(x: 32, y: 55), CGPoint(x: 25, y: 52), CGPoint(x: 15, y: 50), CGPoint(x: 8, y: 44), CGPoint(x: 5, y: 35),
        CGPoint(x: 7, y: 27),
    ]

    public enum Form: Sendable, CaseIterable {
        case africa, circle, wave, bubble
    }

    public static let africa = resample(africaTrace, count: pointCount)
    /// Écoute : une oreille ouverte.
    public static let circle = radial { _ in 44 }
    /// Réflexion : une onde à quatre bosses.
    public static let wave = radial { 42 + 6 * sin(4 * $0) }
    /// Parole : un cercle avec une petite pointe en bas à droite.
    public static let bubble = radial { angle in
        let offset = angle - 0.55 - 2 * Double.pi * ((angle - 0.55) / (2 * Double.pi)).rounded()
        return 44 + 14 * exp(-pow(offset / 0.22, 2))
    }

    public static func points(_ form: Form) -> [CGPoint] {
        switch form {
        case .africa: return africa
        case .circle: return circle
        case .wave: return wave
        case .bubble: return bubble
        }
    }

    // MARK: Barres du contour (les sept barres du logo)

    /// Abscisse, centre vertical et hauteur relevés sur le logo. La quatrième, ambre, est la plus haute.
    public static let barX: [CGFloat] = [21, 29, 37.5, 46.7, 56, 65, 73]
    public static let barY: [CGFloat] = [40.6, 40.2, 40.2, 39.8, 44.5, 43.8, 43.8]
    public static let barHeights: [CGFloat] = [11, 21, 32, 41, 36, 22, 12.5]
    public static let barWidth: CGFloat = 5.3
    public static let amberBar = 3

    // MARK: Repos : l'Afrique dessinée par les barres

    public struct Span: Sendable, Equatable {
        public var top: CGFloat
        public var bottom: CGFloat
    }

    public struct RestingBar: Sendable, Equatable {
        public enum Style: Sendable, Equatable {
            /// Barre du continent (dégradé magenta → cyan).
            case continent
            /// Barre ambre posée DEVANT la barre du continent de même abscisse.
            case amber
            /// Madagascar, trois petites barres à part.
            case madagascar
        }

        public let x: CGFloat
        public let span: Span
        public let style: Style
    }

    /// Relevé sur les fichiers du propriétaire (repos, 1254 × 1254 px, validé le 2026-10-23) : on garde les mesures en
    /// pixels pour pouvoir les recontrôler sur l'image, et on les ramène au repère 0…100 (pixel 260 → 0, 7,4 px par unité).
    static func artwork(_ pixel: CGFloat, origin: CGFloat) -> CGFloat { (pixel - origin) / 7.4 }
    static func artworkX(_ pixel: CGFloat) -> CGFloat { artwork(pixel, origin: 260) }
    static func artworkY(_ pixel: CGFloat) -> CGFloat { artwork(pixel, origin: 250) }

    /// Largeur d'une barre (25 px), épaisseur de la ligne d'onde (22 px), largeur de sa découpe (40 px) et du liseré
    /// autour des barres ambre (6 px).
    public static let restingBarWidth: CGFloat = 25 / 7.4
    public static let waveWidth: CGFloat = 22 / 7.4
    public static let waveCutWidth: CGFloat = 40 / 7.4
    public static let amberEdge: CGFloat = 6 / 7.4

    /// Ordre de dessin : continent, Madagascar, puis les barres ambre (devant).
    public static let restingBars: [RestingBar] = {
        // [x du centre, haut, bas] en pixels.
        let continent: [[CGFloat]] = [
            [281, 534, 583], [322, 508, 610], [363, 444, 600], [402, 403, 545], [440, 358, 505], [479, 326, 505],
            [517, 311, 500], [556, 295, 783], [595, 333, 863], [634, 372, 945], [674, 358, 916], [714, 394, 827],
            [751, 456, 733], [787, 506, 678], [823, 545, 600], [857, 555, 582], [907, 526, 630], [944, 545, 609],
            [981, 561, 591],
        ]
        let madagascar: [[CGFloat]] = [[773, 815, 908], [810, 771, 863], [846, 736, 818]]
        let amber: [[CGFloat]] = [[556, 420, 730], [595, 480, 730]]
        func bars(_ specs: [[CGFloat]], _ style: RestingBar.Style) -> [RestingBar] {
            specs.map { spec in
                RestingBar(x: AVEMarkGeometry.artworkX(spec[0]),
                           span: Span(top: AVEMarkGeometry.artworkY(spec[1]), bottom: AVEMarkGeometry.artworkY(spec[2])),
                           style: style)
            }
        }
        return bars(continent, .continent) + bars(madagascar, .madagascar) + bars(amber, .amber)
    }()

    /// Ligne d'onde qui traverse les barres au repos, en deux tronçons : le « n » violet à gauche, puis la vague qui passe
    /// de l'ambre au cyan et s'enroule vers Madagascar. Points de passage relevés en pixels.
    public static let waveSegments: [[CGPoint]] = {
        let pixels: [[[CGFloat]]] = [
            [[352, 560], [360, 622], [385, 618], [415, 552], [443, 516], [474, 524], [494, 566], [503, 630], [505, 688]],
            [[634, 636], [636, 582], [652, 548], [679, 537], [706, 555], [736, 597], [768, 618], [804, 612], [842, 588],
             [868, 566], [884, 574], [866, 602], [828, 634], [796, 660], [778, 688]],
        ]
        return pixels.map { segment in
            segment.map { CGPoint(x: AVEMarkGeometry.artworkX($0[0]), y: AVEMarkGeometry.artworkY($0[1])) }
        }
    }()

    // MARK: Image à un instant donné

    public struct Frame: Sendable, Equatable {
        /// Contour, en `pointCount` points.
        public var outline: [CGPoint]
        /// Hauteurs des sept barres du contour.
        public var bars: [CGFloat]
        /// Barres de l'Afrique au repos (même ordre que `restingBars`).
        public var resting: [Span]
        /// 1 : on voit l'Afrique en barres (repos) ; 0 : on voit le contour et ses sept barres.
        public var restingOpacity: CGFloat
    }

    /// Image fixe pour « Réduire les animations » : l'Afrique en barres, sans respiration.
    public static let still = Frame(outline: africa, bars: barHeights, resting: restingBars.map(\.span), restingOpacity: 1)

    /// - Parameters:
    ///   - elapsed: secondes depuis l'entrée dans `phase` (enchaînements : naissance, cycle de réflexion).
    ///   - time: horloge continue en secondes (vagues et respiration ; ne repart pas de zéro à chaque changement).
    ///   - level: niveau audio 0…1 (micro en écoute, lecture en parole).
    public static func frame(phase: AVEMarkPhase, elapsed: Double, time: Double, level: Double) -> Frame {
        let level = min(max(level, 0), 1)
        let resting = breathing(time: time)
        switch phase {
        case .launch:
            let bars = barHeights.indices.map { index in
                barHeights[index] * CGFloat(ease((elapsed - 0.7 - Double(index) * 0.09) / 0.26))
            }
            return Frame(outline: mix(circle, africa, CGFloat(ease((elapsed - 0.3) / 0.9))), bars: bars,
                         resting: resting, restingOpacity: 0)
        case .idle:
            return Frame(outline: africa, bars: barHeights, resting: resting, restingOpacity: 1)
        case .listening:
            let bars = barHeights.indices.map { index in
                CGFloat(7 + 34 * level * (0.55 + 0.45 * abs(sin(time * 6.3 + Double(index) * 1.7))))
            }
            return Frame(outline: circle, bars: bars, resting: resting, restingOpacity: 0)
        case .thinking:
            // Afrique → onde → cercle → Afrique, 1,6 s par étape, en boucle.
            let cycle: [Form] = [.africa, .wave, .circle, .africa]
            let position = (max(elapsed, 0) / 1.6).truncatingRemainder(dividingBy: 3)
            let step = min(Int(position), 2)
            let outline = mix(points(cycle[step]), points(cycle[step + 1]), CGFloat(ease(position - Double(step))))
            let bars = barHeights.indices.map { index in
                CGFloat(9 + 28 * (0.5 + 0.5 * sin(time * 4.2 - Double(index) * 0.75)))
            }
            return Frame(outline: outline, bars: bars, resting: resting, restingOpacity: 0)
        case .speaking:
            let bars = barHeights.indices.map { index in
                barHeights[index] * CGFloat(0.55 + 0.6 * level * (0.6 + 0.4 * abs(sin(time * 7 + Double(index) * 0.9))))
            }
            return Frame(outline: bubble, bars: bars, resting: resting, restingOpacity: 0)
        }
    }

    /// Durée du passage d'un état à l'autre.
    public static let transition: Double = 0.45

    /// Passage en douceur de l'image de l'état précédent (qui continue de vivre) à celle du nouvel état.
    public static func blended(from previous: AVEMarkPhase, previousElapsed: Double, to phase: AVEMarkPhase,
                               elapsed: Double, time: Double, level: Double) -> Frame {
        let target = frame(phase: phase, elapsed: elapsed, time: time, level: level)
        let progress = ease(elapsed / transition)
        guard progress < 1, previous != phase else { return target }
        let origin = frame(phase: previous, elapsed: previousElapsed, time: time, level: level)
        return mix(origin, target, CGFloat(progress))
    }

    // MARK: Outils

    /// Respiration lente qui traverse les barres d'ouest en est (± 4 % de hauteur). Le décalage dépend de l'abscisse :
    /// une barre ambre respire avec la barre qu'elle recouvre.
    static func breathing(time: Double) -> [Span] {
        restingBars.map { bar in
            let center = (bar.span.top + bar.span.bottom) / 2
            let half = (bar.span.bottom - bar.span.top) / 2 * CGFloat(1 + 0.04 * sin(time * 1.6 - Double(bar.x) * 0.066))
            return Span(top: center - half, bottom: center + half)
        }
    }

    /// Courbe douce (accélère puis freine), bornée à 0…1.
    public static func ease(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    static func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    static func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: mix(a.x, b.x, t), y: mix(a.y, b.y, t))
    }

    public static func mix(_ a: [CGPoint], _ b: [CGPoint], _ t: CGFloat) -> [CGPoint] {
        zip(a, b).map { mix($0, $1, t) }
    }

    static func mix(_ a: Frame, _ b: Frame, _ t: CGFloat) -> Frame {
        Frame(outline: mix(a.outline, b.outline, t),
              bars: zip(a.bars, b.bars).map { mix($0, $1, t) },
              resting: zip(a.resting, b.resting).map { Span(top: mix($0.top, $1.top, t), bottom: mix($0.bottom, $1.bottom, t)) },
              restingOpacity: mix(a.restingOpacity, b.restingOpacity, t))
    }

    /// Répartit `count` points à égale distance le long du polygone fermé.
    public static func resample(_ polygon: [CGPoint], count: Int) -> [CGPoint] {
        guard polygon.count > 1, count > 0 else { return polygon }
        let closed = polygon + [polygon[0]]
        var lengths: [CGFloat] = [0]
        for index in 1..<closed.count {
            let dx = closed[index].x - closed[index - 1].x
            let dy = closed[index].y - closed[index - 1].y
            lengths.append(lengths[index - 1] + (dx * dx + dy * dy).squareRoot())
        }
        let total = lengths[lengths.count - 1]
        var result: [CGPoint] = []
        result.reserveCapacity(count)
        var segment = 1
        for step in 0..<count {
            let distance = total * CGFloat(step) / CGFloat(count)
            while segment < closed.count - 1 && lengths[segment] < distance { segment += 1 }
            let span = lengths[segment] - lengths[segment - 1]
            let t = span > 0 ? (distance - lengths[segment - 1]) / span : 0
            result.append(mix(closed[segment - 1], closed[segment], t))
        }
        return result
    }

    /// Forme polaire autour du centre du logo, même départ et même sens que l'Afrique.
    static func radial(_ radius: (Double) -> Double) -> [CGPoint] {
        (0..<pointCount).map { step in
            let angle = -2.5 + 2 * Double.pi * Double(step) / Double(pointCount)
            let r = radius(angle)
            return CGPoint(x: 49 + r * cos(angle), y: 50 + r * sin(angle))
        }
    }
}
