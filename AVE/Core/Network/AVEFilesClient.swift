import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Erreurs des routes HTTP de fichiers et de signalement (E16, E17). `code` reprend le code du moteur, pour un seul jeu
/// de messages à l'utilisateur (`UserMessages.mediaError`).
public enum MediaFileError: Error, Sendable, Equatable {
    case fileTooLarge(maxBytes: Int?)
    case unsupportedType
    case featureDisabled
    case unauthorized
    case rateLimited(retryAfterSeconds: Int?)
    case storageFull
    case badRequest
    case notFound
    /// Le moteur n'a pas de stockage des signalements : l'app ne doit PAS dire « signalement envoyé ».
    case reportsDisabled
    case network
    case unavailable

    public var code: String {
        switch self {
        case .fileTooLarge: return "file_too_large"
        case .unsupportedType: return "unsupported_type"
        case .featureDisabled: return "feature_disabled"
        case .unauthorized: return "unauthorized"
        case .rateLimited: return "rate_limited"
        case .storageFull: return "storage_full"
        case .badRequest: return "bad_request"
        case .notFound: return "file_not_found"
        case .reportsDisabled: return "reports_disabled"
        case .network: return "network"
        case .unavailable: return "engine_unavailable"
        }
    }

    public var retryAfterSeconds: Int? {
        if case .rateLimited(let seconds) = self { return seconds }
        return nil
    }
}

/// Routes HTTP du moteur pour les fichiers : envoi d'une pièce jointe, téléchargement d'un résultat, signalement.
/// Même hôte que la WebSocket, même jeton court (jamais journalisé, jamais dans l'URL).
public struct AVEFilesClient: Sendable {
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public let baseURL: URL
    private let tokenProvider: AVETokenProvider
    private let send: Send

    public init(endpoint: AVEEndpoint, tokenProvider: @escaping AVETokenProvider,
                send: @escaping Send = AVEFilesClient.liveSend) throws {
        guard let base = Self.httpBase(for: endpoint) else { throw AVEEndpointError.invalidURL }
        self.baseURL = base
        self.tokenProvider = tokenProvider
        self.send = send
    }

    public static let liveSend: Send = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MediaFileError.network }
        return (data, http)
    }

    /// `wss://hôte/v1/stream` → `https://hôte` ; `ws` (réseau local, développement) → `http`.
    public static func httpBase(for endpoint: AVEEndpoint) -> URL? {
        guard var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme?.lowercased() == "ws" ? "http" : "https"
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// Envoie un fichier BRUT (le moteur reconnaît le type au contenu). `idempotencyKey` : la même clé renvoie le même
    /// `file_id`, ce qui permet de réessayer sans doublon sur un réseau instable.
    public func upload(_ data: Data, idempotencyKey: String) async throws -> UploadedFile {
        guard data.count <= MediaLimits.maxUploadBytes else { throw MediaFileError.fileTooLarge(maxBytes: MediaLimits.maxUploadBytes) }
        var request = try await authorizedRequest("POST", path: "v1/files")
        request.timeoutInterval = 120  // 10 Mo en 3G
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = data
        let json = try await callJSON(request)
        guard let fileID = json["file_id"] as? String, let size = json["size"] as? Int else { throw MediaFileError.unavailable }
        return UploadedFile(fileID: fileID, kind: json["kind"] as? String ?? "", mime: json["mime"] as? String ?? "",
                            size: size, expiresAt: json["expires_at"] as? Int ?? 0)
    }

    /// Télécharge un fichier produit (`task_done.url`). Seuls les chemins `/v1/files/…` du moteur sont acceptés : une
    /// adresse venue du réseau ne doit jamais faire partir le jeton vers un autre hôte.
    public func download(path: String) async throws -> Data {
        guard path.hasPrefix("/v1/files/"), !path.contains(".."), !path.contains("://") else { throw MediaFileError.badRequest }
        var request = try await authorizedRequest("GET", path: String(path.dropFirst()))
        request.timeoutInterval = 120  // jusqu'à 25 Mo pour une image 4K
        let (data, http) = try await perform(request)
        guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, data: data, http: http) }
        return data
    }

    /// Signale un contenu produit (E17). Renvoie l'identifiant du signalement. `reportsDisabled` : rien n'a été gardé.
    public func report(fileID: String, taskID: String?, reason: ReportReason, note: String?) async throws -> String {
        var request = try await authorizedRequest("POST", path: "v1/reports")
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["file_id": fileID, "reason": reason.rawValue]
        if let taskID { body["task_id"] = taskID }
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            body["note"] = String(note.prefix(MediaLimits.reportNoteMaxCharacters))
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await callJSON(request)
        guard let id = json["report_id"] as? String else { throw MediaFileError.unavailable }
        return id
    }

    // MARK: Interne

    private func authorizedRequest(_ method: String, path: String) async throws -> URLRequest {
        let token: String?
        do { token = try await tokenProvider() } catch { throw MediaFileError.unauthorized }
        guard let token, !token.isEmpty else { throw MediaFileError.unauthorized }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do { return try await send(request) } catch let error as MediaFileError { throw error } catch {
            throw MediaFileError.network
        }
    }

    private func callJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, http) = try await perform(request)
        guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, data: data, http: http) }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    static func error(status: Int, data: Data, http: HTTPURLResponse) -> MediaFileError {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let retry = (json["retry_after_s"] as? Int) ?? http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
        switch json["error"] as? String {
        case "file_too_large": return .fileTooLarge(maxBytes: json["max_bytes"] as? Int)
        case "unsupported_type": return .unsupportedType
        case "feature_disabled": return .featureDisabled
        case "unauthorized": return .unauthorized
        case "rate_limited": return .rateLimited(retryAfterSeconds: retry)
        case "storage_full": return .storageFull
        case "bad_request": return .badRequest
        case "file_not_found", "not_found": return .notFound
        case "reports_disabled": return .reportsDisabled
        default: break
        }
        switch status {
        case 401: return .unauthorized
        case 403: return .featureDisabled
        case 404: return .notFound
        case 413: return .fileTooLarge(maxBytes: json["max_bytes"] as? Int)
        case 415: return .unsupportedType
        case 429: return .rateLimited(retryAfterSeconds: retry)
        case 400: return .badRequest
        default: return .unavailable
        }
    }
}
