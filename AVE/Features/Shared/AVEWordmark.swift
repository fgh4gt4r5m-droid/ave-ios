#if os(iOS)
import SwiftUI

/// Le mot « AVE » et son sous-titre (maquette validée le 2026-10-23), dessinés en vecteur et animés à l'entrée dans le
/// style du logo vivant. En sombre, identique au fichier du propriétaire ; en clair, lettres presque noires et dernière
/// barre un peu plus foncée, sinon le gris et le cyan disparaissent sur le blanc. Lu par VoiceOver « AVE, African Voice
/// Engine ». « Réduire les animations » : le mot s'affiche directement.
public struct AVEWordmark: View {
    let width: CGFloat
    let showsSubtitle: Bool
    let animated: Bool
    /// Attente avant l'entrée (pour laisser le logo naître d'abord).
    let delay: Double

    @State private var start = Date()
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    public init(width: CGFloat, showsSubtitle: Bool = true, animated: Bool = true, delay: Double = 0) {
        self.width = width
        self.showsSubtitle = showsSubtitle
        self.animated = animated
        self.delay = delay
    }

    /// Unités du fichier → points.
    private var scale: CGFloat { width / AVEWordmarkGeometry.bounds.width }

    public var body: some View {
        TimelineView(.animation(paused: !animated || reduceMotion || finished)) { timeline in
            let frame = currentFrame(at: timeline.date)
            let dark = colorScheme == .dark
            VStack(spacing: 22 * scale) {
                Canvas { context, size in
                    AVEWordmarkPainter.draw(frame, in: &context, size: size, dark: dark)
                }
                .frame(width: width, height: AVEWordmarkPainter.canvasHeight * scale)
                if showsSubtitle {
                    subtitle(dark: dark)
                        .opacity(frame.subtitleOpacity)
                        .offset(y: frame.subtitleRise * scale)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsSubtitle ? "AVE, African Voice Engine" : "AVE")
        .accessibilityAddTraits(.isHeader)
        .task {
            guard animated, !reduceMotion else {
                finished = true
                return
            }
            start = Date()
            try? await Task.sleep(for: .seconds(delay + AVEWordmarkGeometry.duration + 0.1))
            if !Task.isCancelled { finished = true }
        }
    }

    private func currentFrame(at date: Date) -> AVEWordmarkGeometry.Frame {
        guard animated, !reduceMotion, !finished else { return AVEWordmarkGeometry.still }
        return AVEWordmarkGeometry.frame(elapsed: date.timeIntervalSince(start) - delay)
    }

    /// Vrai texte (net à toutes les tailles), « VOICE » en ambre, étalé sur la largeur du mot comme dans le fichier.
    private func subtitle(dark: Bool) -> some View {
        var text = AttributedString("AFRICAN VOICE ENGINE")
        if let voice = text.range(of: "VOICE") { text[voice].foregroundColor = AVEWordmarkPainter.voice }
        return Text(text)
            .font(.system(size: 34 * scale, weight: .bold))
            .tracking(15 * scale)
            .foregroundStyle(dark ? AVEWordmarkPainter.lettersDark : AVEWordmarkPainter.lettersLight)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: width)
    }
}

/// Dessin du mot à un instant donné. Hors de la vue (non isolé) : appelé depuis le rendu du `Canvas`.
enum AVEWordmarkPainter {
    static let lettersDark = rgb(0xF2F2F2)
    static let lettersLight = rgb(0x1C1C1E)
    static let dot = rgb(0xF5A524)
    static let voice = rgb(0xF1A547)
    static let topBar = rgb(0x3768F6)
    static let middleBar = rgb(0x1FACF1)
    static let cyanDark = rgb(0x02FBF9)
    static let cyanLight = rgb(0x00BFD6)

    /// Marge au-dessus du dessin : le point ambre tombe d'un peu plus haut que le mot.
    static let topMargin: CGFloat = 40
    static var canvasHeight: CGFloat { AVEWordmarkGeometry.bounds.height + topMargin }

    static func draw(_ frame: AVEWordmarkGeometry.Frame, in context: inout GraphicsContext, size: CGSize, dark: Bool) {
        let bounds = AVEWordmarkGeometry.bounds
        let scale = size.width / bounds.width
        func place(_ point: CGPoint) -> CGPoint {
            CGPoint(x: (point.x - bounds.minX) * scale, y: (point.y - bounds.minY + topMargin) * scale)
        }
        let letters = GraphicsContext.Shading.color(dark ? lettersDark : lettersLight)
        let style = StrokeStyle(lineWidth: AVEWordmarkGeometry.stroke * scale, lineCap: .round, lineJoin: .round)

        var a = Path()
        a.move(to: place(AVEWordmarkGeometry.aStart))
        a.addLine(to: place(AVEWordmarkGeometry.aLeftShoulder))
        a.addQuadCurve(to: place(AVEWordmarkGeometry.aRightShoulder), control: place(AVEWordmarkGeometry.aApexControl))
        a.addLine(to: place(AVEWordmarkGeometry.aEnd))
        if frame.aTrim > 0 { context.stroke(a.trimmedPath(from: 0, to: frame.aTrim), with: letters, style: style) }

        var v = Path()
        v.addLines(AVEWordmarkGeometry.vPoints.map(place))
        if frame.vTrim > 0 { context.stroke(v.trimmedPath(from: 0, to: frame.vTrim), with: letters, style: style) }

        let colors = [topBar, middleBar, dark ? cyanDark : cyanLight]
        for (index, bar) in AVEWordmarkGeometry.bars.enumerated() where index < frame.bars.count {
            let length = bar.width * frame.bars[index]
            guard length > 0.5 else { continue }
            let origin = place(bar.origin)
            let rect = CGRect(x: origin.x, y: origin.y, width: length * scale, height: bar.height * scale)
            let radius = min(bar.height, length) * scale / 2
            context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(colors[index]))
        }

        if frame.dotOpacity > 0 {
            let center = place(CGPoint(x: AVEWordmarkGeometry.dotCenter.x, y: AVEWordmarkGeometry.dotCenter.y - frame.dotDrop))
            let radius = AVEWordmarkGeometry.dotRadius * scale
            var layer = context
            layer.opacity = frame.dotOpacity
            layer.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)),
                       with: .color(dot))
        }
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
#endif
