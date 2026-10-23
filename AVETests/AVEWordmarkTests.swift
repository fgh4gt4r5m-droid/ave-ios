import CoreGraphics
import Foundation
import Testing
@testable import AVEKit

/// Le mot AVE et l'écran du numéro : géométrie et données pures.
@Suite("Mot AVE et indicatifs")
struct AVEWordmarkTests {
    @Test("le dessin tient dans sa boîte, qui sert au centrage sous le symbole")
    func drawingFitsBounds() {
        let box = AVEWordmarkGeometry.bounds
        let half = AVEWordmarkGeometry.stroke / 2
        for point in [AVEWordmarkGeometry.aStart, AVEWordmarkGeometry.aEnd] + AVEWordmarkGeometry.vPoints {
            #expect(point.x - half >= box.minX - 0.5 && point.x + half <= box.maxX + 0.5)
            #expect(point.y - half >= box.minY - 0.5 && point.y + half <= box.maxY + 0.5)
        }
        for bar in AVEWordmarkGeometry.bars {
            #expect(box.contains(CGPoint(x: bar.minX, y: bar.minY)) && bar.maxX <= box.maxX && bar.maxY <= box.maxY + 0.5)
        }
        // La barre du milieu du E est la plus courte.
        #expect(AVEWordmarkGeometry.bars[1].width < AVEWordmarkGeometry.bars[0].width)
    }

    @Test("entrée : rien au départ, tout en place à la fin")
    func entranceStartsEmptyAndEndsStill() {
        let start = AVEWordmarkGeometry.frame(elapsed: 0)
        #expect(start.aTrim == 0 && start.vTrim == 0)
        #expect(start.bars.allSatisfy { $0 == 0 })
        #expect(start.dotOpacity == 0 && start.subtitleOpacity == 0)
        let end = AVEWordmarkGeometry.frame(elapsed: AVEWordmarkGeometry.duration)
        #expect(end.aTrim == 1 && end.vTrim == 1 && end.bars == [1, 1, 1])
        #expect(end.dotOpacity == 1 && abs(end.dotDrop) < 0.001)
        #expect(end.subtitleOpacity == 1 && end.subtitleRise == 0)
    }

    @Test("ordre : le A avant le V, les barres du E l'une après l'autre, le point après")
    func entranceOrder() {
        let early = AVEWordmarkGeometry.frame(elapsed: 0.3)
        #expect(early.aTrim > early.vTrim)
        let bars = AVEWordmarkGeometry.frame(elapsed: 0.7).bars
        #expect(bars[0] > bars[1] && bars[1] > bars[2])
        #expect(AVEWordmarkGeometry.frame(elapsed: 0.8).dotOpacity == 0)
        #expect(AVEWordmarkGeometry.frame(elapsed: 0.9).dotOpacity == 1)
    }

    @Test("indicatifs : la Guinée d'abord, indicatifs uniques (ils servent d'étiquettes), drapeaux")
    func countries() {
        #expect(PhoneCountry.all.first?.dialCode == "224")
        #expect(Set(PhoneCountry.all.map(\.dialCode)).count == PhoneCountry.all.count)
        #expect(PhoneCountry.forDialCode("221")?.name == "Sénégal")
        #expect(PhoneCountry.forDialCode("999") == nil)
        #expect(PhoneCountry.forDialCode("224")?.flag == "🇬🇳")
    }
}
