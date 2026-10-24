import Foundation

/// « Créer comme image » (maquette validée le 2026-10-24) : la phrase écrite en mode normal commence-t-elle comme une
/// demande d'image ? L'app ne fait que PROPOSER le mode image ; rien n'est créé sans un toucher. Début de phrase
/// seulement : « explique-moi cette image » ou « une image vaut mille mots » ne déclenchent rien. Comprendre la demande
/// sans ce geste relève du moteur (D12, `ready.engine.image_from_chat`).
public enum ImageIntent {
    /// Formules de politesse acceptées devant la demande.
    private static let openings = ["peux-tu ", "peux tu ", "pourrais-tu ", "pouvez-vous ", "pourriez-vous ", "stp ", "svp "]
    /// Débuts de demande, sans accents ni majuscules.
    private static let requests = [
        "cree une image", "cree-moi une image", "cree moi une image", "creer une image", "cree un dessin",
        "genere une image", "genere-moi une image", "generer une image", "fais une image", "fais-moi une image",
        "fais moi une image", "fait une image", "faire une image", "dessine", "illustre", "imagine une image",
        "une image de ", "une image d'", "une image d\u{2019}", "image de ", "image d'",
    ]

    public static func suggestsImage(_ text: String) -> Bool {
        var folded = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "\u{2019}", with: "'")
        for opening in openings where folded.hasPrefix(opening) {
            folded = String(folded.dropFirst(opening.count))
            break
        }
        // Le mot seul ne suffit pas : il faut au moins un mot de description après la demande.
        guard let request = requests.first(where: { folded.hasPrefix($0) }) else { return false }
        return folded.dropFirst(request.count).contains { $0.isLetter }
    }
}
