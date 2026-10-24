import Foundation

/// Cadence d'écriture d'une réponse qui arrive (D7). Le moteur envoyait un fragment de ≈ 42 caractères toutes les 100 ms,
/// puis ≈ 20 caractères toutes les 40 ms (PR #40, mesuré en ligne le 2026-10-24) ; afficher chacun d'un coup donne un
/// texte qui avance par à-coups. Comme
/// ChatGPT, Claude ou Gemini, l'app dévoile le texte à cadence régulière et rattrape son retard : un cinquième du reste
/// à chaque image (≈ 30 par seconde), au moins trois caractères. Un fragment de 20 caractères apparaît ainsi en
/// ≈ 0,2 s, un de 120 en 0,5 s : le texte coule sans jamais prendre beaucoup de retard sur le moteur. Pur, testé.
public enum StreamReveal {
    public static let frameInterval: Duration = .milliseconds(33)

    /// Nombre de caractères à montrer à l'image suivante.
    public static func next(shown: Int, total: Int) -> Int {
        guard shown < total else { return total }
        return min(total, shown + max(3, (total - shown) / 5))
    }
}
