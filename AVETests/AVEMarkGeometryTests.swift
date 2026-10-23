import CoreGraphics
import Foundation
import Testing
@testable import AVEKit

/// Logo vivant : la géométrie est pure, on vérifie ici ce qui garantit des transformations sans saut.
@Suite("Logo vivant")
struct AVEMarkGeometryTests {
    private func close(_ a: [CGPoint], _ b: [CGPoint], tolerance: CGFloat = 0.001) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0.x - $1.x) < tolerance && abs($0.y - $1.y) < tolerance }
    }

    private func close(_ a: [CGFloat], _ b: [CGFloat], tolerance: CGFloat = 0.001) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < tolerance }
    }

    @Test("toutes les formes ont le même nombre de points, dans le cadre")
    func formsShareThePointCount() {
        for form in AVEMarkGeometry.Form.allCases {
            let points = AVEMarkGeometry.points(form)
            #expect(points.count == AVEMarkGeometry.pointCount)
            #expect(points.allSatisfy { $0.x >= 0 && $0.x <= 100 && $0.y >= 0 && $0.y <= 100 })
        }
    }

    @Test("l'Afrique part du Maroc, comme les formes rondes partent d'en haut à gauche")
    func formsStartAtTheSamePlace() throws {
        let africa = try #require(AVEMarkGeometry.africa.first)
        #expect(africa == CGPoint(x: 10, y: 22))
        let circle = try #require(AVEMarkGeometry.circle.first)
        // Même quart du cadre : pas de rotation d'une forme à l'autre.
        #expect(circle.x < 50 && circle.y < 50)
    }

    @Test("rééchantillonnage : points à égale distance")
    func resampleIsEven() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        let points = AVEMarkGeometry.resample(square, count: 8)
        #expect(close(points, [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 5),
                               CGPoint(x: 10, y: 10), CGPoint(x: 5, y: 10), CGPoint(x: 0, y: 10), CGPoint(x: 0, y: 5)]))
    }

    @Test("au repos : 19 barres de continent, 3 pour Madagascar, 2 ambre devant leur barre")
    func restingBarsDrawAfrica() {
        let bars = AVEMarkGeometry.restingBars
        let continent = bars.filter { $0.style == .continent }
        #expect(continent.count == 19)
        #expect(bars.filter { $0.style == .madagascar }.count == 3)
        let amber = bars.filter { $0.style == .amber }
        #expect(amber.count == 2)
        #expect(bars.allSatisfy { $0.span.top < $0.span.bottom })
        // Chaque barre ambre recouvre une barre du continent de même abscisse, sans en dépasser.
        for bar in amber {
            let under = continent.first { abs($0.x - bar.x) < 0.01 }
            #expect(under != nil)
            #expect((under?.span.top ?? .infinity) <= bar.span.top && bar.span.bottom <= (under?.span.bottom ?? 0))
        }
        // Les barres ambre sont dessinées en dernier (devant).
        #expect(bars.suffix(2).allSatisfy { $0.style == .amber })
        // L'Afrique est plus haute au centre (jusqu'au Cap) qu'à l'ouest et à la corne.
        let tallest = continent.max { ($0.span.bottom - $0.span.top) < ($1.span.bottom - $1.span.top) }
        #expect((tallest?.x ?? 0) > 35 && (tallest?.x ?? 100) < 60)
    }

    @Test("au repos, tout tient dans le cadre (marge de lueur comprise)")
    func restingFitsTheFrame() {
        let inside: (CGPoint) -> Bool = { $0.x >= -5 && $0.x <= 105 && $0.y >= -5 && $0.y <= 105 }
        for bar in AVEMarkGeometry.restingBars {
            #expect(inside(CGPoint(x: bar.x, y: bar.span.top)) && inside(CGPoint(x: bar.x, y: bar.span.bottom)))
        }
        #expect(AVEMarkGeometry.waveSegments.count == 2)
        #expect(AVEMarkGeometry.waveSegments.allSatisfy { $0.count > 2 && $0.allSatisfy(inside) })
    }

    @Test("la barre ambre du contour est la plus haute")
    func amberBarIsTallest() {
        #expect(AVEMarkGeometry.barHeights.max() == AVEMarkGeometry.barHeights[AVEMarkGeometry.amberBar])
        #expect(AVEMarkGeometry.barX.count == AVEMarkGeometry.barHeights.count)
        #expect(AVEMarkGeometry.barY.count == AVEMarkGeometry.barHeights.count)
    }

    @Test("repos : barres visibles ; autres états : contour visible")
    func restingOpacityByPhase() {
        #expect(AVEMarkGeometry.frame(phase: .idle, elapsed: 1, time: 0, level: 0).restingOpacity == 1)
        for phase in [AVEMarkPhase.launch, .listening, .thinking, .speaking] {
            #expect(AVEMarkGeometry.frame(phase: phase, elapsed: 1, time: 0, level: 0).restingOpacity == 0)
        }
    }

    @Test("naissance : un cercle sans barres, qui devient l'Afrique avec ses barres")
    func launchGrowsIntoAfrica() {
        let start = AVEMarkGeometry.frame(phase: .launch, elapsed: 0, time: 0, level: 0)
        #expect(close(start.outline, AVEMarkGeometry.circle))
        #expect(start.bars.allSatisfy { $0 == 0 })
        let end = AVEMarkGeometry.frame(phase: .launch, elapsed: 2, time: 0, level: 0)
        #expect(close(end.outline, AVEMarkGeometry.africa))
        #expect(close(end.bars, AVEMarkGeometry.barHeights))
    }

    @Test("réflexion : Afrique, puis onde, puis cercle, puis retour")
    func thinkingCycles() {
        func outline(at elapsed: Double) -> [CGPoint] {
            AVEMarkGeometry.frame(phase: .thinking, elapsed: elapsed, time: 0, level: 0).outline
        }
        #expect(close(outline(at: 0), AVEMarkGeometry.africa))
        #expect(close(outline(at: 1.6), AVEMarkGeometry.wave))
        #expect(close(outline(at: 3.2), AVEMarkGeometry.circle))
        #expect(close(outline(at: 4.8), AVEMarkGeometry.africa))
    }

    @Test("écoute et parole : les barres suivent le niveau audio")
    func barsFollowLevel() {
        for phase in [AVEMarkPhase.listening, .speaking] {
            let quiet = AVEMarkGeometry.frame(phase: phase, elapsed: 1, time: 0.3, level: 0).bars.reduce(0, +)
            let loud = AVEMarkGeometry.frame(phase: phase, elapsed: 1, time: 0.3, level: 1).bars.reduce(0, +)
            #expect(loud > quiet)
        }
        // Un niveau hors bornes est ramené à 0…1.
        let clamped = AVEMarkGeometry.frame(phase: .listening, elapsed: 1, time: 0.3, level: 5)
        let full = AVEMarkGeometry.frame(phase: .listening, elapsed: 1, time: 0.3, level: 1)
        #expect(clamped == full)
    }

    @Test("changement d'état : part de l'image précédente, arrive à la nouvelle")
    func blendIsContinuous() {
        let start = AVEMarkGeometry.blended(from: .idle, previousElapsed: 5, to: .listening, elapsed: 0, time: 1, level: 0)
        let idle = AVEMarkGeometry.frame(phase: .idle, elapsed: 5, time: 1, level: 0)
        #expect(close(start.outline, idle.outline))
        #expect(start.restingOpacity == 1)
        let end = AVEMarkGeometry.blended(from: .idle, previousElapsed: 6, to: .listening,
                                          elapsed: AVEMarkGeometry.transition, time: 1, level: 0)
        #expect(end == AVEMarkGeometry.frame(phase: .listening, elapsed: AVEMarkGeometry.transition, time: 1, level: 0))
    }

    @Test("correspondance avec l'état de la session")
    func phaseFromOrb() {
        #expect(AVEMarkPhase(orb: .listening) == .listening)
        #expect(AVEMarkPhase(orb: .thinking) == .thinking)
        #expect(AVEMarkPhase(orb: .speaking) == .speaking)
        for orb in [OrbState.idle, .interrupted, .reconnecting, .unavailable] {
            #expect(AVEMarkPhase(orb: orb) == .idle)
        }
    }

    @Test("« Réduire les animations » : l'Afrique en barres, fixe")
    func stillFrameIsResting() {
        #expect(AVEMarkGeometry.still.restingOpacity == 1)
        #expect(AVEMarkGeometry.still.resting == AVEMarkGeometry.restingBars.map(\.span))
    }
}
