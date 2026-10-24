import Foundation

/// Cadence d'écriture d'une réponse qui arrive (D7). Le moteur envoie environ deux fragments par phrase (mesuré en
/// ligne le 2026-10-24 : 44 fragments pour 19 phrases) ; afficher chacun d'un coup donne un texte « par blocs ». Comme
/// ChatGPT, Claude ou Gemini, l'app dévoile le texte à cadence régulière et rattrape son retard : un cinquième du reste
/// à chaque image (≈ 30 par seconde), au moins trois caractères. Un fragment apparaît ainsi en ≈ 0,3 s, quelle que
/// soit sa taille, et le texte ne prend jamais plus d'une demi-seconde de retard sur le moteur. Pur, testé.
public enum StreamReveal {
    public static let frameInterval: Duration = .milliseconds(33)

    /// Nombre de caractères à montrer à l'image suivante.
    public static func next(shown: Int, total: Int) -> Int {
        guard shown < total else { return total }
        return min(total, shown + max(3, (total - shown) / 5))
    }
}
