import Foundation
import Testing
@testable import AVEKit

/// Icônes au choix : les noms du code, de project.yml et du catalogue d'images doivent concorder, sinon iOS refuse
/// le changement d'icône (et rien ne le dit avant l'essai sur l'iPhone).
@Suite("Icônes au choix")
struct AppIconChoiceTests {
    /// Racine du dépôt, à partir de ce fichier (AVETests/…).
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }

    @Test("l'icône d'origine d'abord, puis six alternatives aux noms uniques")
    func choices() {
        let choices = AppIconChoice.ave
        #expect(choices.first?.alternateName == nil)
        #expect(choices.count == 7)
        #expect(Set(choices.map(\.id)).count == choices.count)
        #expect(AppIconChoice.current(alternateName: nil, in: choices)?.title == "Ruban, d'origine")
        #expect(AppIconChoice.current(alternateName: "AppIcon-Barres3D-Nuit", in: choices)?.id == "Barres3D-Nuit")
        #expect(AppIconChoice.current(alternateName: "AppIcon-Inconnue", in: choices) == nil)
    }

    @Test("mêmes noms que project.yml")
    func matchesProjectFile() throws {
        let yml = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        let line = try #require(yml.split(separator: "\n").first { $0.contains("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES") })
        let declared = Set(line.split(separator: "\"").dropFirst().first?.split(separator: " ").map(String.init) ?? [])
        let coded = Set(AppIconChoice.ave.compactMap(\.alternateName))
        #expect(declared == coded)
    }

    @Test("chaque icône et chaque aperçu existent dans le catalogue, en clair, sombre (et teinté)")
    func assetsExist() throws {
        let assets = root.appendingPathComponent("AVE/App/Assets.xcassets")
        for choice in AppIconChoice.ave {
            let preview = assets.appendingPathComponent("\(choice.previewImage).imageset/Contents.json")
            let previewJSON = try String(contentsOf: preview, encoding: .utf8)
            #expect(previewJSON.contains("\"dark\""))
            guard let name = choice.alternateName else { continue }
            let icon = assets.appendingPathComponent("\(name).appiconset/Contents.json")
            let iconJSON = try String(contentsOf: icon, encoding: .utf8)
            #expect(iconJSON.contains("\"dark\"") && iconJSON.contains("\"tinted\""))
        }
    }
}
