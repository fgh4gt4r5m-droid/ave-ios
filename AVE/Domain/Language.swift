/// Codes de langue du protocole (`hello.lang`), ISO 639-3 comme le registre du serveur
/// (`sdk/ts/src/protocol.ts` : LANG_CODES). Le statut réel de chaque langue vient de `ready.languages`.
public enum AVELanguage: String, Sendable, CaseIterable, Codable {
    case soussou = "sus"
    case peul = "ful"
    case malinke = "man"
    case french = "fra"
    case bambara = "bam"
    case lingala = "lin"
    case swahili = "swa"
    case wolof = "wol"
    case yoruba = "yor"
    case zulu = "zul"
    case auto
}

/// Une langue telle qu'annoncée par `ready.languages` / `GET /v1/languages`.
/// Le code reste une chaîne : le registre serveur peut s'enrichir sans casser le décodage.
public struct LanguageInfo: Sendable, Equatable, Decodable {
    public let code: String
    public let name: String
    public let native: String
    public let status: String          // planned | experimental | production
    /// Le serveur sait la traiter MAINTENANT ; `nil` = inconnu.
    public let available: Bool?
}
