#if os(iOS)
import SwiftUI

/// Logo vivant d'AVE (maquettes validées le 2026-10-23) : au repos, l'Afrique dessinée par les barres, qui respire ;
/// en écoute, réflexion et parole, l'Afrique en contour se transforme pendant que les sept barres pulsent.
///
/// Dessiné en vecteur dans un `Canvas` piloté par `TimelineView` : la forme et chaque barre bougent séparément, ce que
/// l'image `AVELogo` ne permet pas. Décoratif : masqué pour VoiceOver, l'appelant dit l'état par du texte.
/// « Réduire les animations » : l'Afrique en barres, fixe.
public struct AVELiveMark: View {
    let phase: AVEMarkPhase
    let level: Float

    /// État affiché ; diffère de `phase` pendant la naissance (`entrance`).
    @State private var shown: AVEMarkPhase
    @State private var previous: AVEMarkPhase
    @State private var changedAt = Date()
    @State private var previousStartedAt = Date()
    /// Dernier état demandé, lu à la fin de la naissance (la valeur de `phase` capturée par la tâche serait périmée).
    @State private var requested: AVEMarkPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - level: niveau audio 0…1 (micro en écoute, lecture en parole) ; ignoré dans les autres états.
    ///   - entrance: joue d'abord la naissance du logo (lancement, bienvenue).
    public init(phase: AVEMarkPhase, level: Float = 0, entrance: Bool = false) {
        self.phase = phase
        self.level = level
        let first: AVEMarkPhase = entrance ? .launch : phase
        _shown = State(initialValue: first)
        _previous = State(initialValue: first)
        _requested = State(initialValue: phase)
    }

    public var body: some View {
        // Au repos, la respiration est lente : 30 images/s suffisent et ménagent la batterie.
        TimelineView(.animation(minimumInterval: shown == .idle ? 1.0 / 30 : nil, paused: reduceMotion)) { timeline in
            let frame = currentFrame(at: timeline.date)
            Canvas { context, size in
                AVEMarkPainter.draw(frame, in: &context, size: size)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .onChange(of: phase) { _, new in
            requested = new
            if shown != .launch { move(to: new) }
        }
        .task(id: shown) {
            guard shown == .launch else { return }
            try? await Task.sleep(for: .milliseconds(1700))
            guard !Task.isCancelled else { return }
            move(to: requested)
        }
    }

    private func currentFrame(at date: Date) -> AVEMarkGeometry.Frame {
        if reduceMotion { return AVEMarkGeometry.still }
        return AVEMarkGeometry.blended(from: previous, previousElapsed: date.timeIntervalSince(previousStartedAt),
                                       to: shown, elapsed: date.timeIntervalSince(changedAt),
                                       time: date.timeIntervalSinceReferenceDate, level: Double(level))
    }

    private func move(to new: AVEMarkPhase) {
        guard new != shown else { return }
        previous = shown
        previousStartedAt = changedAt
        shown = new
        changedAt = Date()
    }
}

/// Dessin d'une image du logo. Hors de la vue (non isolé) : appelé depuis le rendu du `Canvas`.
enum AVEMarkPainter {
    // Couleurs du logo (dessin de marque, identiques en clair et en sombre, comme l'icône).
    static let outlineColors = [rgb(0x3FB6FF), rgb(0x4F6BFF), rgb(0xA855F7)]
    static let barColors = [rgb(0x45A8FF), rgb(0x8B5CF6)]
    static let amberColors = [rgb(0xFFD54A), rgb(0xFF9F1C)]
    // Repos : relevées sur les fichiers du propriétaire.
    static var restingStops: [Gradient.Stop] { [
        .init(color: rgb(0xE11DF5), location: 0), .init(color: rgb(0x7C3AED), location: 0.35),
        .init(color: rgb(0x3B5BFF), location: 0.55), .init(color: rgb(0x14B4FF), location: 0.8),
        .init(color: rgb(0x00E5FF), location: 1),
    ] }
    static var waveStops: [Gradient.Stop] { [
        .init(color: rgb(0xC026F5), location: 0), .init(color: rgb(0x8B3DF5), location: 0.3),
        .init(color: rgb(0xFFB020), location: 0.5), .init(color: rgb(0xFFB020), location: 0.56),
        .init(color: rgb(0x3FA9FF), location: 0.66), .init(color: rgb(0x00E5FF), location: 1),
    ] }
    static var amberStops: [Gradient.Stop] { [
        .init(color: rgb(0xFFE08A), location: 0), .init(color: rgb(0xFFB020), location: 0.55),
        .init(color: rgb(0xFF8A5B), location: 1),
    ] }

    static func draw(_ frame: AVEMarkGeometry.Frame, in context: inout GraphicsContext, size: CGSize) {
        // Repère 0…100 + marge de 10 de chaque côté pour la lueur.
        let scale = min(size.width, size.height) / 120
        let origin = CGPoint(x: (size.width - 120 * scale) / 2, y: (size.height - 120 * scale) / 2)
        func place(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + (x + 10) * scale, y: origin.y + (y + 10) * scale)
        }
        let contour = 1 - frame.restingOpacity
        if contour > 0.01 {
            var layer = context
            layer.opacity = contour
            drawOutline(frame, in: &layer, scale: scale, place: place)
        }
        if frame.restingOpacity > 0.01 {
            var layer = context
            layer.opacity = frame.restingOpacity
            drawResting(frame, in: &layer, scale: scale, place: place)
        }
    }

    private static func drawOutline(_ frame: AVEMarkGeometry.Frame, in context: inout GraphicsContext, scale: CGFloat,
                                    place: (CGFloat, CGFloat) -> CGPoint) {
        let path = smoothPath(frame.outline.map { place($0.x, $0.y) })
        let shading = GraphicsContext.Shading.linearGradient(Gradient(colors: outlineColors),
                                                             startPoint: place(0, 0), endPoint: place(100, 100))
        let style = StrokeStyle(lineWidth: 7.5 * scale, lineCap: .round, lineJoin: .round)
        // Lueur : le même trait, flouté, sous le trait net.
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 2.2 * scale))
            glow.opacity = 0.7
            glow.stroke(path, with: shading, style: style)
        }
        context.stroke(path, with: shading, style: style)

        let width = AVEMarkGeometry.barWidth
        let barShading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: barColors),
            startPoint: place(AVEMarkGeometry.barX[0], 0), endPoint: place(AVEMarkGeometry.barX[6], 0))
        for index in frame.bars.indices where index < AVEMarkGeometry.barX.count {
            let height = frame.bars[index]
            guard height > 0.5 else { continue }  // naissance : barre pas encore montée
            let drawn = max(height, width)
            let x = AVEMarkGeometry.barX[index], y = AVEMarkGeometry.barY[index]
            let topLeft = place(x - width / 2, y - drawn / 2)
            let rect = CGRect(x: topLeft.x, y: topLeft.y, width: width * scale, height: drawn * scale)
            let capsule = Path(roundedRect: rect, cornerRadius: width * scale / 2)
            if index == AVEMarkGeometry.amberBar {
                context.fill(capsule, with: .linearGradient(Gradient(colors: amberColors),
                                                            startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                            endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            } else {
                context.fill(capsule, with: barShading)
            }
        }
    }

    /// Repos, recalé sur les fichiers du propriétaire : barres du continent et de Madagascar, deux barres ambre devant
    /// (avec un liseré), puis la ligne d'onde qui DÉCOUPE les barres qu'elle croise. Liseré et découpe se font par
    /// effacement (`destinationOut`) dans un calque à part : ils restent justes sur n'importe quel fond, clair ou sombre.
    private static func drawResting(_ frame: AVEMarkGeometry.Frame, in context: inout GraphicsContext, scale: CGFloat,
                                    place: (CGFloat, CGFloat) -> CGPoint) {
        let width = AVEMarkGeometry.restingBarWidth
        // Les mesures sont en unités du logo ; le dégradé suit l'abscisse du continent (ouest magenta, est cyan).
        let barShading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: restingStops), startPoint: place(AVEMarkGeometry.artworkX(270), 0),
            endPoint: place(AVEMarkGeometry.artworkX(990), 0))
        let waveShading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: waveStops), startPoint: place(AVEMarkGeometry.artworkX(270), 0),
            endPoint: place(AVEMarkGeometry.artworkX(990), 0))
        func capsule(x: CGFloat, span: AVEMarkGeometry.Span, margin: CGFloat = 0) -> Path {
            let barWidth = width + 2 * margin
            let height = max(span.bottom - span.top + 2 * margin, barWidth)
            let topLeft = place(x - barWidth / 2, span.top - margin)
            let rect = CGRect(x: topLeft.x, y: topLeft.y, width: barWidth * scale, height: height * scale)
            return Path(roundedRect: rect, cornerRadius: barWidth * scale / 2)
        }
        var bars = Path()
        var amber: [Path] = []
        var amberEdges: [Path] = []
        for (bar, span) in zip(AVEMarkGeometry.restingBars, frame.resting) {
            switch bar.style {
            case .continent, .madagascar:
                bars.addPath(capsule(x: bar.x, span: span))
            case .amber:
                amber.append(capsule(x: bar.x, span: span))
                amberEdges.append(capsule(x: bar.x, span: span, margin: AVEMarkGeometry.amberEdge))
            }
        }
        let waves = AVEMarkGeometry.waveSegments.map { segment in openSmoothPath(segment.map { place($0.x, $0.y) }) }
        let cutStyle = StrokeStyle(lineWidth: AVEMarkGeometry.waveCutWidth * scale, lineCap: .round, lineJoin: .round)
        let waveStyle = StrokeStyle(lineWidth: AVEMarkGeometry.waveWidth * scale, lineCap: .round, lineJoin: .round)

        func compose(_ layer: inout GraphicsContext) {
            layer.fill(bars, with: barShading)
            for (bar, edge) in zip(amber, amberEdges) {
                layer.blendMode = .destinationOut
                layer.fill(edge, with: .color(.black))
                layer.blendMode = .normal
                let box = bar.boundingRect
                layer.fill(bar, with: .linearGradient(Gradient(stops: amberStops),
                                                      startPoint: CGPoint(x: box.midX, y: box.minY),
                                                      endPoint: CGPoint(x: box.midX, y: box.maxY)))
            }
            for wave in waves {
                layer.blendMode = .destinationOut
                layer.stroke(wave, with: .color(.black), style: cutStyle)
                layer.blendMode = .normal
                layer.stroke(wave, with: waveShading, style: waveStyle)
            }
        }
        // Lueur : la même composition, floutée, sous la composition nette.
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 5 / 7.4 * scale))
            glow.opacity = 0.6
            compose(&glow)
        }
        context.drawLayer { sharp in compose(&sharp) }
    }

    /// Courbe fermée passant par tous les points (Catmull-Rom converti en courbes de Bézier).
    static func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        let count = points.count
        guard count > 2 else { return path }
        path.move(to: points[0])
        for index in 0..<count {
            let p0 = points[(index - 1 + count) % count], p1 = points[index]
            let p2 = points[(index + 1) % count], p3 = points[(index + 2) % count]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return path
    }

    /// Courbe ouverte passant par tous les points (Catmull-Rom, extrémités répétées).
    static func openSmoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first, points.count > 1 else { return path }
        path.move(to: first)
        let last = points.count - 1
        for index in 0..<last {
            let p0 = points[max(index - 1, 0)], p1 = points[index]
            let p2 = points[index + 1], p3 = points[min(index + 2, last)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        return path
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
#endif
