import Foundation

/// Les fichiers de la conversation (photos jointes, images et documents produits), gardés SUR L'IPHONE : le moteur les
/// oublie au bout d'1 h. Chaque fichier vit dans son propre dossier pour garder son vrai nom (partage, aperçu, Fichiers).
public protocol MediaStore: Sendable {
    /// Enregistre et renvoie le nom à garder dans le message (`<uuid>/<nom>`), ou `nil` si l'écriture échoue.
    func save(_ data: Data, fileName: String) -> String?
    func url(for name: String) -> URL?
    func data(for name: String) -> Data?
    /// Efface tout ce qui n'est plus cité par aucune conversation (historique désactivé, conversation effacée).
    func purge(keeping names: Set<String>)
}

/// Application Support/Media, exclu des sauvegardes iCloud, protégé comme l'historique.
public final class FileMediaStore: MediaStore, @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func standard() -> FileMediaStore? {
        guard var base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        base.appendPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)
        return FileMediaStore(directory: base)
    }

    /// Un nom venu de l'historique ne doit jamais sortir du dossier (`../`).
    static func isSafe(_ name: String) -> Bool {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && UUID(uuidString: String(parts[0])) != nil && !parts[1].isEmpty
            && parts[1] != "." && parts[1] != ".." && !name.contains("\\")
    }

    /// Nom de fichier propre : sans séparateur, sans caractère de contrôle, longueur raisonnable.
    static func sanitized(_ fileName: String) -> String {
        let cleaned = fileName.unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) || "/\\:".unicodeScalars.contains($0) ? "-" : Character($0) }
        var name = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." { name = "fichier" }
        guard name.count > 80 else { return name }
        let ext = (name as NSString).pathExtension
        let stem = String((name as NSString).deletingPathExtension.prefix(70))
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    public func save(_ data: Data, fileName: String) -> String? {
        let folder = UUID().uuidString
        let name = "\(folder)/\(Self.sanitized(fileName))"
        lock.lock()
        defer { lock.unlock() }
        let dir = directory.appendingPathComponent(folder, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            #if os(iOS)
            try data.write(to: directory.appendingPathComponent(name),
                           options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            #endif
        } catch {
            return nil
        }
        return name
    }

    public func url(for name: String) -> URL? {
        guard Self.isSafe(name) else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func data(for name: String) -> Data? {
        guard let url = url(for: name) else { return nil }
        return try? Data(contentsOf: url)
    }

    public func purge(keeping names: Set<String>) {
        let folders = Set(names.filter(Self.isSafe).compactMap { $0.split(separator: "/").first.map(String.init) })
        lock.lock()
        defer { lock.unlock() }
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where !folders.contains(entry.lastPathComponent) {
            try? FileManager.default.removeItem(at: entry)
        }
    }
}
