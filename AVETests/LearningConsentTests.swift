import Foundation
import Testing
@testable import AVECore
@testable import AVEKit

@Suite("Règles du consentement")
struct LearningConsentTests {
    private let offer = LearningStatus(available: true, enabled: false, noticeVersion: "2026-10-v1")

    @Test("demandé seulement si disponible, pas déjà accepté, pas refusé pour cette version, pas déjà sollicité")
    func shouldAsk() {
        #expect(LearningConsent.shouldAsk(status: offer, language: .french, declinedVersion: nil, askedThisSession: false))
        #expect(!LearningConsent.shouldAsk(status: nil, language: .french, declinedVersion: nil, askedThisSession: false))
        #expect(!LearningConsent.shouldAsk(status: LearningStatus(available: false, enabled: false, noticeVersion: "2026-10-v1"),
                                           language: .french, declinedVersion: nil, askedThisSession: false))
        #expect(!LearningConsent.shouldAsk(status: LearningStatus(available: true, enabled: true, noticeVersion: "2026-10-v1"),
                                           language: .french, declinedVersion: nil, askedThisSession: false))
        #expect(!LearningConsent.shouldAsk(status: offer, language: .french, declinedVersion: "2026-10-v1", askedThisSession: false))
        #expect(!LearningConsent.shouldAsk(status: offer, language: .french, declinedVersion: nil, askedThisSession: true))
    }

    @Test("un refus ancien ne bloque pas une NOUVELLE version de la notice")
    func newVersionAsksAgain() {
        let v2 = LearningNoticeText(version: "2026-11-v2", languages: [.french], speechLanguageCode: "fr-FR",
                                    title: "t", body: "b", yes: "o", no: "n")
        let status = LearningStatus(available: true, enabled: false, noticeVersion: "2026-11-v2")
        #expect(LearningConsent.shouldAsk(status: status, language: .french, declinedVersion: "2026-10-v1",
                                          askedThisSession: false, notices: [v2]))
    }

    @Test("notice exacte requise : version ET langue ; aucune notice locale inventée")
    func noticeLookup() {
        #expect(LearningNotice.text(version: "2026-10-v1", language: .french) != nil)
        #expect(LearningNotice.text(version: "2026-10-v1", language: .auto) != nil)
        #expect(LearningNotice.text(version: "2099-01-v9", language: .french) == nil)
        for local in [AVELanguage.soussou, .peul, .malinke, .wolof, .bambara] {
            #expect(LearningNotice.text(version: "2026-10-v1", language: local) == nil)
        }
    }

    @Test("la notice dit l'essentiel : refus sans conséquence, retrait possible, limite de l'oubli")
    func noticeContent() throws {
        let n = try #require(LearningNotice.text(version: "2026-10-v1", language: .french))
        #expect(n.body.contains("Vous pouvez refuser : l'application marche exactement pareil."))
        #expect(n.body.contains("effacées") && n.body.contains("ne peut pas oublier"))
        #expect(n.yes == "Oui, j'aide" && n.no == "Non merci")
        #expect(n.spokenText.hasPrefix(n.title))
    }

    @Test("mémoire locale : uniquement la version refusée")
    func preferences() {
        let p = InMemoryLearningPreferences()
        #expect(p.declinedVersion == nil)
        p.declinedVersion = "2026-10-v1"
        #expect(p.declinedVersion == "2026-10-v1")
    }
}
