import AVECore

/// Langues proposées. Liste CODÉE EN DUR en attendant `GET /v1/languages` (contrat E6) : les statuts
/// reflètent le serveur du sprint 1, où seul le français a un moteur.
public struct LanguageOption: Identifiable, Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case available
        /// Pas de moteur côté serveur : le tour échouerait avec `language_unavailable`.
        case unavailable
    }

    public let language: AVELanguage
    public let name: String
    public let nativeName: String?
    public let status: Status
    public let detail: String

    public var id: String { language.rawValue }
    public var isAvailable: Bool { status == .available }
}

public enum LanguageCatalog {
    public static let builtIn: [LanguageOption] = [
        LanguageOption(language: .french, name: "Français", nativeName: nil, status: .available,
                       detail: "Disponible"),
        LanguageOption(language: .soussou, name: "Soussou", nativeName: "Sosoxui", status: .unavailable,
                       detail: "Pas encore disponible : l'assistant ne pourra pas répondre."),
        LanguageOption(language: .peul, name: "Peul (Pular)", nativeName: "Pular", status: .unavailable,
                       detail: "Pas encore disponible : l'assistant ne pourra pas répondre."),
        LanguageOption(language: .malinke, name: "Malinké", nativeName: "Maninkakan", status: .unavailable,
                       detail: "Pas encore disponible : l'assistant ne pourra pas répondre."),
        LanguageOption(language: .auto, name: "Détection automatique", nativeName: nil, status: .available,
                       detail: "Aujourd'hui, seul le français est compris."),
    ]

    public static func option(for language: AVELanguage) -> LanguageOption? {
        builtIn.first { $0.language == language }
    }
}
