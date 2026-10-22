/// `ready.learning` : l'apprentissage à partir des conversations, avec consentement explicite.
/// Ne demander l'accord que si `available` est vrai ET `enabled` faux. Les tenants institutionnels ne voient jamais `available: true`.
public struct LearningStatus: Sendable, Equatable, Decodable {
    public let available: Bool
    /// L'utilisateur a déjà consenti à CETTE version de la notice.
    public let enabled: Bool
    public let noticeVersion: String

    public init(available: Bool, enabled: Bool, noticeVersion: String) {
        self.available = available
        self.enabled = enabled
        self.noticeVersion = noticeVersion
    }

    enum CodingKeys: String, CodingKey {
        case available, enabled, noticeVersion = "notice_version"
    }
}
