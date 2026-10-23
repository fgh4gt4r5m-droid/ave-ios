import Foundation

/// Conditions d'utilisation et politique de confidentialité montrées à l'entrée. BROUILLONS (2026-10-23) à faire relire
/// par un juriste avant toute publication : changer leur texte de fond impose de changer `currentVersion`, et l'app
/// redemande alors l'accord à chacun. Ce qui est dit ici décrit ce que l'app et ses services font réellement à cette date.
public enum Terms {
    /// Version acceptée, gardée par le service de comptes (`terms_version`) et sur l'iPhone.
    /// v2 (2026-10-23) : la dictée par la reconnaissance vocale d'Apple, sur l'iPhone.
    public static let currentVersion = "2026-10-v2"
    public static let minimumAge = 18

    public static let draftNotice = "Brouillon : ce texte sera relu par un juriste avant la publication d'AVE."

    /// Conditions d'utilisation (la partie « contenus créés par IA » reprend `CGU-CONTENUS-IA.md`).
    public static let conditions = """
    ## Qui peut utiliser AVE
    AVE est réservé aux personnes de 18 ans ou plus. En créant un compte, vous confirmez avoir cet âge.

    ## Ce que fait AVE
    AVE est un assistant : il répond à vos questions à l'écrit et à la voix, et peut, à votre demande, créer ou modifier des images et traduire, résumer ou reformuler des documents. Ses réponses sont produites par une intelligence artificielle : elles peuvent être inexactes. Vérifiez les informations importantes.

    ## Ce que vous vous engagez à respecter
    - Ne joindre que des photos et des documents que vous avez le droit d'utiliser.
    - Ne retoucher la photo d'une personne réelle qu'avec son accord, ou si vous êtes vous-même cette personne.
    - Ne pas utiliser AVE pour tromper, harceler, diffamer ou humilier une personne.

    Sont interdites les demandes et les images comportant de la nudité ou un caractère sexuel ; des mineurs dans un contexte sexuel, violent ou dégradant ; des scènes sanglantes, de la violence ou de la cruauté ; des contenus dangereux (armes, explosifs, drogues, mise en danger) ; de la haine ou de la discrimination ; et plus généralement tout contenu de même nature. AVE refuse ces demandes. Les comptes qui cherchent à contourner ces règles peuvent être suspendus.

    ## Responsabilité
    Vous êtes seul responsable des demandes que vous faites, des fichiers que vous joignez et de l'usage que vous faites des contenus produits. AVE décline toute responsabilité si une photo d'une personne réelle, ou un contenu produit par AVE, est détourné à des fins contraires à ces règles.

    ## Signaler
    Chaque image produite peut être signalée depuis l'application. Elle est aussitôt masquée sur votre iPhone, et le signalement est examiné par une personne.

    ## Votre compte
    Vous pouvez supprimer votre compte à tout moment depuis les réglages : votre profil et vos accès sont effacés.
    """

    /// Politique de confidentialité : ce qui est gardé, où, et combien de temps.
    public static let privacy = """
    ## Votre compte
    - Numéro de téléphone : le service de comptes n'en garde qu'une empreinte, jamais le numéro lui-même. Le code reçu par SMS ou WhatsApp n'est gardé que sous forme d'empreinte.
    - Compte Apple : seule une empreinte de votre identifiant Apple est gardée, et le jeton qui permet de révoquer la connexion Apple est chiffré.
    - Nom complet : gardé chiffré, pour vous saluer. Vous pouvez le changer dans les réglages.
    - Conditions et âge : la version acceptée et la date sont gardées.

    ## Vos conversations
    L'historique de vos conversations reste sur votre iPhone. Vous pouvez l'effacer à tout moment, ou ne plus le garder. Le serveur d'AVE ne garde pas vos conversations après la fin de la session.

    ## La dictée
    Le micro de la barre de saisie utilise la reconnaissance vocale d'Apple, sur votre iPhone : le son ne quitte pas l'appareil et n'est pas gardé. Le texte dicté n'est envoyé à AVE que si vous touchez Envoyer.

    ## Vos fichiers
    Les photos et documents que vous joignez, et les contenus produits, sont effacés des serveurs d'AVE au bout d'une heure. Ils ne servent jamais à entraîner l'IA. Une image que vous signalez est conservée le temps de son examen.

    ## Aider à améliorer AVE
    C'est facultatif et cela vous est demandé à part. Sans votre accord, rien de ce que vous dites ou écrivez n'est gardé pour améliorer AVE. Vous pouvez retirer votre aide à tout moment, et ce qui avait été gardé est alors effacé.

    ## Supprimer votre compte
    Depuis les réglages. Votre profil, vos accès et ce que vous aviez accepté de partager pour améliorer AVE sont effacés.
    """
}
