import Foundation

/// Une conversation gardée SUR L'IPHONE (historique, comme ChatGPT ou Claude). Le moteur ne garde rien : rouvrir une
/// conversation la réaffiche, mais l'assistant repart sans mémoire (une nouvelle session), ce que l'écran doit dire.
/// Les cartes d'action ne sont pas gardées : une action proposée hier n'a plus de sens aujourd'hui.
public struct StoredConversation: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var languageCode: String
    public var messages: [StoredMessage]

    public init(id: UUID = UUID(), title: String, createdAt: Date, updatedAt: Date, languageCode: String,
                messages: [StoredMessage]) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.languageCode = languageCode
        self.messages = messages
    }
}

public struct StoredMessage: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable { case user, assistant, system }
    public var role: Role
    public var text: String
    public var interrupted: Bool
    public var voiceOnly: Bool

    public init(role: Role, text: String, interrupted: Bool = false, voiceOnly: Bool = false) {
        self.role = role
        self.text = text
        self.interrupted = interrupted
        self.voiceOnly = voiceOnly
    }
}

/// Stockage de l'historique. `Sendable` : utilisé depuis l'acteur principal et des tâches.
public protocol ConversationStore: Sendable {
    func list() -> [StoredConversation]
    func save(_ conversation: StoredConversation)
    func delete(id: UUID)
    func deleteAll()
}

/// Un fichier JSON par conversation dans le dossier de l'app (Application Support), protégé par iOS tant que l'iPhone n'a
/// pas été déverrouillé une première fois. Petits volumes (quelques centaines de conversations) : pas de base de données.
public final class FileConversationStore: ConversationStore, @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()  // les écritures peuvent venir de plusieurs tâches

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Dossier par défaut : Application Support/Conversations (exclu des sauvegardes iCloud : données locales seulement).
    public static func standard() -> FileConversationStore? {
        guard var base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        base.appendPathComponent("Conversations", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)
        return FileConversationStore(directory: base)
    }

    private func url(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    public func list() -> [StoredConversation] {
        lock.lock()
        defer { lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(StoredConversation.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ conversation: StoredConversation) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(conversation) else { return }
        lock.lock()
        defer { lock.unlock() }
        #if os(iOS)
        try? data.write(to: url(for: conversation.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: url(for: conversation.id), options: .atomic)
        #endif
    }

    public func delete(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url(for: id))
    }

    public func deleteAll() {
        lock.lock()
        defer { lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" { try? FileManager.default.removeItem(at: file) }
    }
}

/// Pour les tests et les apps hôtes qui ne veulent pas d'historique sur disque.
public final class InMemoryConversationStore: ConversationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UUID: StoredConversation] = [:]

    public init() {}

    public func list() -> [StoredConversation] {
        lock.withLock { items.values.sorted { $0.updatedAt > $1.updatedAt } }
    }

    public func save(_ conversation: StoredConversation) { lock.withLock { items[conversation.id] = conversation } }
    public func delete(id: UUID) { lock.withLock { _ = items.removeValue(forKey: id) } }
    public func deleteAll() { lock.withLock { items.removeAll() } }
}

/// Règles de l'historique, pures et testées : titre, regroupement par date, recherche, conversion du fil.
public enum ConversationHistory {
    public static let titleLength = 40

    /// Titre automatique : la première question de la personne, raccourcie (comme les assistants de référence).
    public static func title(for messages: [StoredMessage]) -> String {
        guard let first = messages.first(where: { $0.role == .user && !$0.text.isEmpty })?.text else {
            return "Conversation vocale"
        }
        let line = first.split(whereSeparator: \.isNewline).first.map(String.init) ?? first
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > titleLength else { return trimmed }
        return String(trimmed.prefix(titleLength)).trimmingCharacters(in: .whitespaces) + "…"
    }

    public enum Section: String, CaseIterable, Sendable {
        case today = "Aujourd'hui"
        case yesterday = "Hier"
        case lastWeek = "7 derniers jours"
        case lastMonth = "30 derniers jours"
        case older = "Plus ancien"
    }

    public static func section(for date: Date, now: Date, calendar: Calendar = .current) -> Section {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        let startOfToday = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: startOfToday).day ?? 0
        switch days {
        case ...1: return .yesterday
        case ...7: return .lastWeek
        case ...30: return .lastMonth
        default: return .older
        }
    }

    public struct Group: Identifiable, Sendable, Equatable {
        public let section: Section
        public let items: [StoredConversation]
        public var id: Section { section }
    }

    /// Conversations regroupées par date de dernière activité, sections vides retirées, ordre récent d'abord.
    public static func grouped(_ conversations: [StoredConversation], now: Date,
                               calendar: Calendar = .current) -> [Group] {
        let sorted = conversations.sorted { $0.updatedAt > $1.updatedAt }
        return Section.allCases.compactMap { section in
            let items = sorted.filter { self.section(for: $0.updatedAt, now: now, calendar: calendar) == section }
            return items.isEmpty ? nil : Group(section: section, items: items)
        }
    }

    /// Recherche dans les titres et les messages, sans tenir compte des accents ni des majuscules.
    public static func search(_ query: String, in conversations: [StoredConversation]) -> [StoredConversation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return conversations }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return conversations.filter { conversation in
            conversation.title.range(of: q, options: options) != nil
                || conversation.messages.contains { $0.text.range(of: q, options: options) != nil }
        }
    }

    /// Ce qu'on garde du fil : les messages lisibles, sans cartes d'action ni bulles en cours de construction vides.
    public static func stored(from messages: [ChatMessage]) -> [StoredMessage] {
        messages.compactMap { message in
            guard message.card == nil else { return nil }
            let role: StoredMessage.Role
            switch message.role {
            case .user: role = .user
            case .assistant: role = .assistant
            case .system: role = .system
            }
            if message.text.isEmpty && !message.isVoiceOnly { return nil }
            // Messages système (erreurs, « reprise sans mémoire ») : utiles sur le moment, pas dans l'historique.
            if role == .system { return nil }
            return StoredMessage(role: role, text: message.text, interrupted: message.status == .interrupted,
                                 voiceOnly: message.isVoiceOnly)
        }
    }
}
