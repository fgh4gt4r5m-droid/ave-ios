/// Codes de langue du protocole (`hello.lang`), ISO 639-3 comme côté serveur.
/// Les statuts affichables (disponible / indisponible) sont une affaire d'UI (étape 4).
public enum AVELanguage: String, Sendable, CaseIterable, Codable {
    case soussou = "sus"
    case peul = "ful"
    case malinke = "man"
    case french = "fra"
    case auto
}
