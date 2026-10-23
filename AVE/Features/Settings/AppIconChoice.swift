import Foundation

/// Icône de l'app au choix (décision du propriétaire, 2026-10-23 : « je les prends tous, tri final plus tard ») :
/// l'icône d'origine et les six compositions 3D (ruban ou barres, sur fond ivoire, clair coloré ou bleu nuit).
/// Chaque alternative a ses versions claire, sombre (bleu nuit) et teintée dans le catalogue d'images.
public struct AppIconChoice: Identifiable, Sendable, Equatable {
    /// Suffixe du jeu d'icône (`AppIcon-<id>`) ; vide pour l'icône principale.
    public let id: String
    public let title: String

    /// Nom à donner à `setAlternateIconName` (`nil` : icône principale).
    public var alternateName: String? { id.isEmpty ? nil : "AppIcon-\(id)" }
    /// Aperçu affiché dans les réglages (une icône d'app ne se charge pas comme une image ordinaire).
    public var previewImage: String { "IconPreview-\(id.isEmpty ? "Defaut" : id)" }

    /// Les icônes de l'app AVE. Les noms doivent être ceux de `project.yml`
    /// (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`) : un test le vérifie.
    public static let ave: [AppIconChoice] = [
        AppIconChoice(id: "", title: "Ruban, d'origine"),
        AppIconChoice(id: "Ruban3D-Ivoire", title: "Ruban 3D, ivoire"),
        AppIconChoice(id: "Ruban3D-Clair", title: "Ruban 3D, clair"),
        AppIconChoice(id: "Ruban3D-Nuit", title: "Ruban 3D, bleu nuit"),
        AppIconChoice(id: "Barres3D-Ivoire", title: "Barres 3D, ivoire"),
        AppIconChoice(id: "Barres3D-Clair", title: "Barres 3D, clair"),
        AppIconChoice(id: "Barres3D-Nuit", title: "Barres 3D, bleu nuit"),
    ]

    /// Choix correspondant à l'icône active (`UIApplication.alternateIconName`).
    public static func current(alternateName: String?, in choices: [AppIconChoice]) -> AppIconChoice? {
        choices.first { $0.alternateName == alternateName }
    }
}
