import AVECore
import Foundation

/// Notice de consentement, versionnée comme côté serveur (`NOTICE_VERSION`). Texte PROPOSÉ par le serveur
/// (docs/APPRENTISSAGE.md) : à relire par un juriste ; AUCUNE traduction en langue locale n'est inventée ici
/// (elles viendront de locuteurs natifs). Tant qu'il n'existe pas de notice dans la langue de l'utilisateur, on ne demande rien.
public struct LearningNoticeText: Sendable, Equatable {
    public let version: String
    /// Langues dans lesquelles cette notice est rédigée (et peut être lue à voix haute).
    public let languages: Set<AVELanguage>
    /// Code BCP 47 pour la synthèse vocale du système.
    public let speechLanguageCode: String
    public let title: String
    public let body: String
    public let yes: String
    public let no: String

    public init(version: String, languages: Set<AVELanguage>, speechLanguageCode: String,
                title: String, body: String, yes: String, no: String) {
        self.version = version
        self.languages = languages
        self.speechLanguageCode = speechLanguageCode
        self.title = title
        self.body = body
        self.yes = yes
        self.no = no
    }

    /// Texte complet, lu à voix haute.
    public var spokenText: String { "\(title) \(body)" }
}

public enum LearningNotice {
    public static let frenchV1 = LearningNoticeText(
        version: "2026-10-v1",
        languages: [.french, .auto],  // « auto » : le serveur ne comprend que le français aujourd'hui
        speechLanguageCode: "fr-FR",
        title: "Aidez AVE à mieux comprendre votre langue.",
        body: """
        Si vous acceptez, vos messages (voix et textes) pourront être gardés et écoutés par l'équipe AVE pour améliorer le service. \
        Les longs numéros sont masqués. \
        Vous pouvez refuser : l'application marche exactement pareil. \
        Vous pouvez arrêter quand vous voulez : vos données de travail seront effacées. \
        Un logiciel déjà entraîné ne peut pas oublier ce qu'il a appris ; nous vous retirerons du suivant.
        """,
        yes: "Oui, j'aide",
        no: "Non merci")

    public static let all: [LearningNoticeText] = [frenchV1]

    /// La notice correspondant EXACTEMENT à la version du serveur et à la langue de l'utilisateur, sinon `nil`
    /// (on ne demande jamais un accord sur un texte qu'on n'a pas montré, ni dans une langue qu'il ne comprend peut-être pas).
    public static func text(version: String, language: AVELanguage, in notices: [LearningNoticeText] = all) -> LearningNoticeText? {
        notices.first { $0.version == version && $0.languages.contains(language) }
    }
}

/// Mémoire locale du REFUS (version de la notice refusée) : pas de relance en boucle. Rien d'autre n'est gardé.
public protocol LearningPreferences: AnyObject, Sendable {
    var declinedVersion: String? { get set }
}

public final class InMemoryLearningPreferences: LearningPreferences, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    public init(declinedVersion: String? = nil) { value = declinedVersion }
    public var declinedVersion: String? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

public final class UserDefaultsLearningPreferences: LearningPreferences, @unchecked Sendable {
    private let key = "ave.learning.declinedNoticeVersion"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var declinedVersion: String? {
        get { defaults.string(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}

public enum LearningConsent {
    /// Faut-il demander l'accord MAINTENANT ? Seulement si le serveur l'autorise (`available`), que l'utilisateur n'a pas déjà
    /// consenti (`enabled`), n'a pas déjà refusé CETTE version, n'a pas déjà été sollicité pendant cette session, et qu'une notice
    /// exacte existe dans sa langue.
    public static func shouldAsk(status: LearningStatus?, language: AVELanguage, declinedVersion: String?,
                                 askedThisSession: Bool, notices: [LearningNoticeText] = LearningNotice.all) -> Bool {
        guard let status, status.available, !status.enabled, !askedThisSession else { return false }
        guard declinedVersion != status.noticeVersion else { return false }
        return LearningNotice.text(version: status.noticeVersion, language: language, in: notices) != nil
    }
}

/// Notice affichée : la version est figée à l'affichage, et c'est elle qui est renvoyée au serveur.
public struct LearningPrompt: Sendable, Equatable {
    public let notice: LearningNoticeText
    public var version: String { notice.version }
}
