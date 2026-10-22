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
    private static let unavailable = "Pas encore disponible : l'assistant ne pourra pas répondre."

    /// Repli quand le serveur n'a pas annoncé ses langues (`ready.languages`) : seul le français est dit disponible.
    public static let builtIn: [LanguageOption] = [
        LanguageOption(language: .french, name: "Français", nativeName: nil, status: .available, detail: "Disponible"),
        LanguageOption(language: .soussou, name: "Soussou", nativeName: "Sosoxui", status: .unavailable, detail: unavailable),
        LanguageOption(language: .peul, name: "Peul (Pular)", nativeName: "Pular", status: .unavailable, detail: unavailable),
        LanguageOption(language: .malinke, name: "Malinké", nativeName: "Maninkakan", status: .unavailable, detail: unavailable),
        LanguageOption(language: .bambara, name: "Bambara", nativeName: "Bamanankan", status: .unavailable, detail: unavailable),
        LanguageOption(language: .wolof, name: "Wolof", nativeName: "Wolof", status: .unavailable, detail: unavailable),
        LanguageOption(language: .lingala, name: "Lingala", nativeName: "Lingála", status: .unavailable, detail: unavailable),
        LanguageOption(language: .swahili, name: "Swahili", nativeName: "Kiswahili", status: .unavailable, detail: unavailable),
        LanguageOption(language: .yoruba, name: "Yoruba", nativeName: "Yorùbá", status: .unavailable, detail: unavailable),
        LanguageOption(language: .zulu, name: "Zoulou", nativeName: "isiZulu", status: .unavailable, detail: unavailable),
        LanguageOption(language: .auto, name: "Détection automatique", nativeName: nil, status: .available,
                       detail: "Le serveur choisit la langue ; seules les langues disponibles sont comprises."),
    ]

    public static func option(for language: AVELanguage) -> LanguageOption? {
        builtIn.first { $0.language == language }
    }

    /// Liste affichée : les langues annoncées par le serveur avec leur disponibilité RÉELLE, sinon le repli.
    /// Les codes inconnus de l'app sont ignorés (on ne peut pas les demander).
    public static func options(from server: [LanguageInfo]?) -> [LanguageOption] {
        guard let server, !server.isEmpty else { return builtIn }
        var options: [LanguageOption] = server.compactMap { info in
            guard let language = AVELanguage(rawValue: info.code) else { return nil }
            let native = info.native == info.name ? nil : info.native
            switch info.available {
            case .some(true):
                let note = info.status == "production" ? "Disponible" : "Disponible (\(info.status == "experimental" ? "expérimental" : info.status))"
                return LanguageOption(language: language, name: info.name, nativeName: native, status: .available, detail: note)
            case .some(false):
                return LanguageOption(language: language, name: info.name, nativeName: native, status: .unavailable, detail: unavailable)
            case .none:
                return LanguageOption(language: language, name: info.name, nativeName: native, status: .unavailable,
                                      detail: "Disponibilité inconnue : l'assistant pourrait ne pas répondre.")
            }
        }
        if let auto = builtIn.first(where: { $0.language == .auto }) { options.append(auto) }
        return options
    }
}
