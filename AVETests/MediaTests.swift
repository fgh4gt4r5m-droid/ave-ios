import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AVECore
@testable import AVEKit

// Fichiers, documents et images (E16, E17) : messages, client HTTP, fil de conversation, historique, session.

/// Faux moteur HTTP : enregistre les requêtes et répond selon le chemin.
final class FakeFilesServer: @unchecked Sendable {
    struct Reply {
        var status: Int
        var body: Data
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private var replies: [String: Reply] = [:]

    func reply(_ path: String, status: Int, json: String, headers: [String: String] = [:]) {
        lock.withLock { replies[path] = Reply(status: status, body: Data(json.utf8), headers: headers) }
    }

    func reply(_ path: String, status: Int, data: Data) {
        lock.withLock { replies[path] = Reply(status: status, body: data) }
    }

    var requests: [URLRequest] { lock.withLock { _requests } }

    var send: AVEFilesClient.Send {
        { [self] request in
            guard let url = request.url else { throw MediaFileError.network }
            let reply: Reply? = lock.withLock {
                _requests.append(request)
                return replies[url.path]
            }
            guard let reply, let http = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                                        headerFields: reply.headers) else {
                throw MediaFileError.network
            }
            return (reply.body, http)
        }
    }
}

private func endpoint() throws -> AVEEndpoint {
    try AVEEndpoint(try #require(URL(string: "wss://ave-engine.test/v1/stream")))
}

private func client(_ server: FakeFilesServer, token: String? = "jeton-court") throws -> AVEFilesClient {
    try AVEFilesClient(endpoint: try endpoint(), tokenProvider: { token }, send: server.send)
}

/// Petite image PNG fabriquée sur place (aucun fichier de test à embarquer).
func makePNG(width: Int, height: Int) throws -> Data {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output as CFMutableData,
                                                                    UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

@Suite("Fichiers et images : protocole")
struct MediaProtocolTests {
    private func object(_ m: ClientMessage) throws -> [String: Any] {
        let s = try m.jsonString()
        return try #require(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    @Test("image_generate : description, format, qualité, ref")
    func generate() throws {
        let o = try object(.task(.imageGenerate(prompt: "Un marché", size: .landscape, quality: .uhd, ref: "r1")))
        #expect(o["type"] as? String == "image_generate")
        #expect(o["prompt"] as? String == "Un marché")
        #expect(o["size"] as? String == "landscape" && o["quality"] as? String == "4k" && o["ref"] as? String == "r1")
        let bare = try object(.task(.imageGenerate(prompt: "x", size: nil, quality: nil, ref: "r2")))
        #expect(bare["size"] == nil && bare["quality"] == nil)
    }

    @Test("retouches : rights_confirmed est un BOOLÉEN, absent pour une image d'AVE")
    func edits() throws {
        let edit = try object(.task(.imageEdit(fileID: "f1", instruction: "fond flou", quality: nil, rightsConfirmed: true,
                                                ref: "r")))
        #expect(edit["type"] as? String == "image_edit" && edit["file_id"] as? String == "f1")
        #expect(edit["instruction"] as? String == "fond flou")
        #expect(edit["rights_confirmed"] as? Bool == true)
        // JSONSerialization lit `true` comme NSNumber : on vérifie aussi le texte brut, pas "true" entre guillemets.
        let raw = try ClientMessage.task(.imageEdit(fileID: "f1", instruction: "x", quality: nil, rightsConfirmed: true,
                                                    ref: "r")).jsonString()
        #expect(raw.contains(#""rights_confirmed":true"#))
        let upscale = try object(.task(.imageUpscale(fileID: "f2", target: .hd, rightsConfirmed: nil, ref: "r")))
        #expect(upscale["type"] as? String == "image_upscale" && upscale["target"] as? String == "1080p")
        #expect(upscale["rights_confirmed"] == nil)
        let extend = try object(.task(.imageExtend(fileID: "f3", aspect: .portrait, quality: nil, rightsConfirmed: true,
                                                    ref: "r")))
        #expect(extend["type"] as? String == "image_extend" && extend["aspect"] as? String == "portrait")
    }

    @Test("document_transform et task_cancel")
    func documentAndCancel() throws {
        let doc = try object(.task(.documentTransform(fileID: "d1", action: .translate, targetLang: "eng", instruction: nil,
                                                       ref: "r")))
        #expect(doc["type"] as? String == "document_transform" && doc["action"] as? String == "translate")
        #expect(doc["target_lang"] as? String == "eng" && doc["instruction"] == nil)
        let cancel = try object(.taskCancel(taskID: "t9"))
        #expect(cancel["type"] as? String == "task_cancel" && cancel["task_id"] as? String == "t9")
    }

    @Test("task_started, task_done, task_error ; simulated absent = simulé")
    func events() throws {
        let started = try ServerFrame.decode(#"{"type":"task_started","seq":4,"task_id":"t1","ref":"r1","kind":"image_generate","estimated_s":35}"#)
        #expect(started.seq == 4)
        #expect(started.event == .taskStarted(MediaTaskStarted(taskID: "t1", ref: "r1", kind: .imageGenerate, estimatedSeconds: 35)))
        let done = try ServerFrame.decode(#"{"type":"task_done","seq":5,"task_id":"t1","ref":"r1","kind":"image_generate","file_id":"f9","file_kind":"png","mime":"image/png","size":1200,"expires_at":1800000000,"url":"/v1/files/f9","width":1920,"height":1920}"#)
        guard case .taskDone(let result) = done.event else { Issue.record("pas task_done"); return }
        #expect(result.simulated)  // champ absent : on avertit plutôt que de présenter un faux comme vrai
        #expect(result.url == "/v1/files/f9" && result.width == 1920 && result.fileKind == "png")
        let error = try ServerFrame.decode(#"{"type":"task_error","seq":6,"task_id":null,"ref":"r2","kind":"image_generate","code":"quota_exceeded","retry_after_s":3600}"#)
        #expect(error.event == .taskError(MediaTaskFailure(taskID: nil, ref: "r2", kind: .imageGenerate, code: "quota_exceeded",
                                                          retryAfterSeconds: 3600)))
    }
}

@Suite("Fichiers et images : client HTTP")
struct MediaFilesClientTests {
    @Test("adresse HTTP déduite de la WebSocket : même hôte, https")
    func base() throws {
        #expect(AVEFilesClient.httpBase(for: try endpoint())?.absoluteString == "https://ave-engine.test")
    }

    @Test("envoi : POST /v1/files, corps brut, jeton en en-tête, clé d'idempotence")
    func upload() async throws {
        let server = FakeFilesServer()
        server.reply("/v1/files", status: 201,
                     json: #"{"file_id":"f1","kind":"pdf","mime":"application/pdf","size":3,"expires_at":1800000000}"#)
        let uploaded = try await client(server).upload(Data([1, 2, 3]), idempotencyKey: "k1")
        #expect(uploaded == UploadedFile(fileID: "f1", kind: "pdf", mime: "application/pdf", size: 3, expiresAt: 1_800_000_000))
        let request = try #require(server.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://ave-engine.test/v1/files")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jeton-court")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "k1")
        #expect(request.httpBody == Data([1, 2, 3]))
        #expect(request.url?.query == nil)  // jamais de jeton dans l'URL
    }

    @Test("erreurs du moteur : code JSON d'abord, sinon statut HTTP")
    func errors() async throws {
        let server = FakeFilesServer()
        let files = try client(server)
        server.reply("/v1/files", status: 413, json: #"{"error":"file_too_large","max_bytes":10485760}"#)
        await #expect(throws: MediaFileError.fileTooLarge(maxBytes: 10_485_760)) {
            _ = try await files.upload(Data([1]), idempotencyKey: "k")
        }
        server.reply("/v1/files", status: 429, json: #"{"error":"rate_limited","retry_after_s":12}"#)
        await #expect(throws: MediaFileError.rateLimited(retryAfterSeconds: 12)) {
            _ = try await files.upload(Data([1]), idempotencyKey: "k")
        }
        server.reply("/v1/files", status: 403, json: "")
        await #expect(throws: MediaFileError.featureDisabled) { _ = try await files.upload(Data([1]), idempotencyKey: "k") }
        // Trop lourd : refusé sur l'iPhone, rien n'est envoyé.
        let before = server.requests.count
        await #expect(throws: MediaFileError.fileTooLarge(maxBytes: MediaLimits.maxUploadBytes)) {
            _ = try await files.upload(Data(count: MediaLimits.maxUploadBytes + 1), idempotencyKey: "k")
        }
        #expect(server.requests.count == before)
    }

    @Test("sans jeton : unauthorized, rien n'est envoyé")
    func noToken() async throws {
        let server = FakeFilesServer()
        await #expect(throws: MediaFileError.unauthorized) {
            _ = try await client(server, token: nil).upload(Data([1]), idempotencyKey: "k")
        }
        #expect(server.requests.isEmpty)
    }

    @Test("téléchargement : seuls les chemins /v1/files du moteur reçoivent le jeton")
    func download() async throws {
        let server = FakeFilesServer()
        server.reply("/v1/files/f9", status: 200, data: Data([9, 9]))
        let files = try client(server)
        #expect(try await files.download(path: "/v1/files/f9") == Data([9, 9]))
        for bad in ["https://ailleurs.test/v1/files/f9", "/v1/files/../tokens", "/autre/f9"] {
            await #expect(throws: MediaFileError.badRequest) { _ = try await files.download(path: bad) }
        }
        #expect(server.requests.count == 1)
    }

    @Test("état d'une tâche : les vecteurs `http` du contrat (D1), un par état, et le 404")
    func taskStatusVectors() async throws {
        let server = FakeFilesServer()
        let files = try client(server)
        server.reply("/v1/tasks/t_44", status: 200,
                     json: #"{"task_id": "t_44", "ref": "r4", "kind": "image_generate", "state": "running"}"#)
        #expect(try await files.taskStatus(taskID: "t_44") == .running)
        server.reply("/v1/tasks/t_44", status: 200, json: #"{"task_id": "t_44", "ref": "r4", "kind": "image_generate", "state": "done", "file_id": "f_a1b2", "file_kind": "jpeg", "mime": "image/jpeg", "size": 2871204, "expires_at": 1792741200, "url": "/v1/files/f_a1b2", "simulated": false, "width": 3840, "height": 2160}"#)
        #expect(try await files.taskStatus(taskID: "t_44") == .done(MediaTaskResult(
            taskID: "t_44", ref: "r4", kind: .imageGenerate, fileID: "f_a1b2", fileKind: "jpeg", mime: "image/jpeg",
            size: 2_871_204, expiresAt: 1_792_741_200, url: "/v1/files/f_a1b2", simulated: false, width: 3840, height: 2160)))
        server.reply("/v1/tasks/t_46", status: 200, json: #"{"task_id": "t_46", "ref": "r8", "kind": "document_transform", "state": "done", "file_id": "f_c3d4", "file_kind": "txt", "mime": "text/plain; charset=utf-8", "size": 1834, "expires_at": 1792741500, "url": "/v1/files/f_c3d4", "simulated": true}"#)
        guard case .done(let document) = try await files.taskStatus(taskID: "t_46") else {
            Issue.record("pas done")
            return
        }
        #expect(document.simulated && document.width == nil && document.mime == "text/plain; charset=utf-8")
        server.reply("/v1/tasks/t_45", status: 200,
                     json: #"{"task_id": "t_45", "ref": "r6", "kind": "image_upscale", "state": "error", "code": "content_refused"}"#)
        #expect(try await files.taskStatus(taskID: "t_45") == .failed(code: "content_refused"))
        server.reply("/v1/tasks/t_42", status: 200,
                     json: #"{"task_id": "t_42", "ref": "r1", "kind": "image_generate", "state": "error", "code": "cancelled"}"#)
        #expect(try await files.taskStatus(taskID: "t_42") == .failed(code: "cancelled"))
        server.reply("/v1/tasks/t_inconnue", status: 404, json: #"{"error":"task_not_found"}"#)
        await #expect(throws: MediaFileError.notFound) { _ = try await files.taskStatus(taskID: "t_inconnue") }
        // Un identifiant venu du réseau ne peut rien ajouter au chemin.
        let before = server.requests.count
        await #expect(throws: MediaFileError.badRequest) { _ = try await files.taskStatus(taskID: "../files/f1") }
        #expect(server.requests.count == before)
    }

    @Test("signalement : 202 → identifiant ; 503 reports_disabled → l'app ne dit pas « envoyé »")
    func report() async throws {
        let server = FakeFilesServer()
        server.reply("/v1/reports", status: 202, json: #"{"report_id":"rep1"}"#)
        let files = try client(server)
        #expect(try await files.report(fileID: "f1", taskID: "t1", reason: .realPerson, note: "  ") == "rep1")
        let body = try #require(server.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["file_id"] as? String == "f1" && json["task_id"] as? String == "t1")
        #expect(json["reason"] as? String == "real_person")
        #expect(json["note"] == nil)  // note vide : non envoyée
        server.reply("/v1/reports", status: 503, json: #"{"error":"reports_disabled"}"#)
        await #expect(throws: MediaFileError.reportsDisabled) {
            _ = try await files.report(fileID: "f1", taskID: nil, reason: .other, note: nil)
        }
    }
}

@Suite("Fichiers et images : conversation et historique")
struct MediaTranscriptTests {
    private func document(fileID: String? = "f1") -> MediaItem {
        MediaItem(kind: .document, origin: .attachment, title: "contrat-bail.pdf", localName: "\(UUID().uuidString)/contrat-bail.pdf",
                  mime: "application/pdf", byteCount: 320_000, fileID: fileID, expiresAt: fileID == nil ? nil : 1_800_000_000)
    }

    @Test("une tâche : envoi → en cours → téléchargement ; un rejeu du moteur ne change rien")
    func taskFlow() {
        var t = ChatTranscript()
        let request = MediaTaskRequest.imageGenerate(prompt: "x", size: nil, quality: nil, ref: "r1")
        let id = t.appendTask(MediaTaskCard(ref: "r1", request: request, resultTitle: "Image"))
        let now = Date(timeIntervalSince1970: 1000)
        t.applyTask(.taskStarted(MediaTaskStarted(taskID: "t1", ref: "r1", kind: .imageGenerate, estimatedSeconds: 35)), now: now)
        #expect(t.message(id)?.task?.state == .working(startedAt: now, estimatedSeconds: 35))
        #expect(t.message(id)?.task?.taskID == "t1")
        let result = MediaTaskResult(taskID: "t1", ref: "r1", kind: .imageGenerate, fileID: "f9", fileKind: "png",
                                     mime: "image/png", size: 10, expiresAt: 1_800_000_000, url: "/v1/files/f9",
                                     simulated: true, width: 1920, height: 1920)
        let first = t.applyTask(.taskDone(result))
        #expect(first?.messageID == id)
        #expect(t.message(id)?.task?.state == .downloading)
        let replayed = t.applyTask(.taskDone(result))  // rejeu à la reprise de session
        #expect(replayed?.messageID == nil)
        // Un événement d'une AUTRE demande ne touche pas cette carte.
        let other = t.applyTask(.taskError(MediaTaskFailure(taskID: nil, ref: "autre", kind: nil, code: "failed",
                                                            retryAfterSeconds: nil)))
        #expect(other?.messageID == nil)
        #expect(t.message(id)?.task?.state == .downloading)
    }

    @Test("annulation et refus : la carte le dit, sans détail de modération")
    func cancelAndRefuse() {
        var t = ChatTranscript()
        let a = t.appendTask(MediaTaskCard(ref: "a", request: .imageGenerate(prompt: "x", size: nil, quality: nil, ref: "a"),
                                           resultTitle: "Image"))
        let b = t.appendTask(MediaTaskCard(ref: "b", request: .imageGenerate(prompt: "y", size: nil, quality: nil, ref: "b"),
                                           resultTitle: "Image"))
        t.applyTask(.taskError(MediaTaskFailure(taskID: "t", ref: "a", kind: nil, code: "cancelled", retryAfterSeconds: nil)))
        t.applyTask(.taskError(MediaTaskFailure(taskID: nil, ref: "b", kind: nil, code: "content_refused", retryAfterSeconds: nil)))
        #expect(t.message(a)?.task?.state == .cancelled)
        #expect(t.message(b)?.task?.state == .failed(code: "content_refused", retryAfterSeconds: nil))
        #expect(UserMessages.mediaError(code: "content_refused") == "Je ne peux pas créer cette image. Essayez une autre demande.")
    }

    @Test("historique : fichiers prêts gardés, cartes et envois échoués écartés, anciens historiques lisibles")
    func history() throws {
        var t = ChatTranscript()
        t.appendAttachment(document())
        var failed = document(fileID: nil)
        failed.state = .failed(code: "file_too_large")
        t.appendAttachment(failed)
        t.appendTask(MediaTaskCard(ref: "r", request: .imageGenerate(prompt: "x", size: nil, quality: nil, ref: "r"),
                                   resultTitle: "Image"))
        let stored = ConversationHistory.stored(from: t.messages)
        #expect(stored.count == 1)
        #expect(stored.first?.media?.title == "contrat-bail.pdf")
        #expect(ConversationHistory.title(for: stored) == "contrat-bail.pdf")
        // Rouvert : même fichier ; `file_id` gardé même expiré, pour pouvoir encore signaler (D3).
        let restored = ChatTranscript(restoring: stored)
        #expect(restored.messages.first?.media?.fileID == "f1")
        #expect(restored.messages.first?.media?.localName == stored.first?.media?.localName)
        // Historique d'avant les fichiers : pas de champ `media`.
        let old = try JSONDecoder().decode(StoredMessage.self, from: Data(#"{"role":"user","text":"salut","interrupted":false,"voiceOnly":false}"#.utf8))
        #expect(old.media == nil && old.text == "salut")
    }

    @Test("case d'accord : photo jointe, ou image d'AVE oubliée par le moteur ; jamais pour un document")
    func rightsRule() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let photo = MediaItem(kind: .image, origin: .attachment, title: "p.jpg", localName: nil, mime: "image/jpeg",
                              byteCount: 1, fileID: "f", expiresAt: 1_003_600)
        var generated = photo
        generated.origin = .generated
        #expect(photo.requiresRightsForTask(now: now))
        #expect(!generated.requiresRightsForTask(now: now))
        generated.expiresAt = 1_000_060  // moins de 2 min : considéré comme oublié
        #expect(generated.requiresRightsForTask(now: now))
        #expect(!document().requiresRightsForTask(now: now))
    }

    @Test("libellés, noms de fichiers, durées")
    func texts() {
        #expect(MediaTaskText.documentResultTitle(source: "contrat-bail.pdf", action: .translate, targetLang: "eng")
                == "contrat-bail (anglais).txt")
        #expect(MediaTaskText.documentResultTitle(source: "note.docx", action: .summarize, targetLang: nil) == "note (résumé).txt")
        #expect(MediaTaskText.userLabel(action: .translate, targetLang: "fra", instruction: nil) == "Traduire en français")
        #expect(MediaTaskText.estimate(35) == "Environ 35 s")
        #expect(MediaTaskText.estimate(120) == "Environ 2 min")
        #expect(MediaTaskText.estimate(nil) == nil)
        #expect(UserMessages.mediaError(code: "quota_exceeded", retryAfterSeconds: 5400)
                == "Vous avez atteint la limite pour aujourd'hui. Réessayez dans 2 h.")
        #expect(UserMessages.mediaError(code: "storage_full") == UserMessages.mediaError(code: "engine_unavailable"))
        #expect(MediaTaskRequest.imageEdit(fileID: "a", instruction: "i", quality: nil, rightsConfirmed: true, ref: "r")
                    .replacing(fileID: "b", ref: "s")
                == .imageEdit(fileID: "b", instruction: "i", quality: nil, rightsConfirmed: true, ref: "s"))
    }
}

@Suite("Fichiers et images : photos et stockage sur l'iPhone")
struct MediaLocalTests {
    @Test("recadrage au centre : carré, portrait 9:16, paysage 16:9")
    func centerCrop() {
        #expect(ImageProcessing.centerCrop(width: 4000, height: 3000, aspect: .square) == CGRect(x: 500, y: 0, width: 3000, height: 3000))
        let portrait = ImageProcessing.centerCrop(width: 4000, height: 3000, aspect: .portrait)
        #expect(portrait.height == 3000 && abs(portrait.width / portrait.height - 9.0 / 16.0) < 0.01)
        let landscape = ImageProcessing.centerCrop(width: 3000, height: 4000, aspect: .landscape)
        #expect(landscape.width == 3000 && abs(landscape.width / landscape.height - 16.0 / 9.0) < 0.01)
    }

    @Test("préparation : un PNG léger passe tel quel ; recadrer rend un JPEG au bon format")
    func prepareAndCrop() throws {
        let png = try makePNG(width: 400, height: 300)
        let prepared = try #require(ImageProcessing.prepareForUpload(png))
        #expect(prepared.mime == "image/png" && prepared.data == png && prepared.width == 400 && prepared.height == 300)
        // Plus grande que 4096 px : réduite et réencodée en JPEG.
        let wide = try #require(ImageProcessing.prepareForUpload(try makePNG(width: 5000, height: 100)))
        #expect(wide.mime == "image/jpeg" && max(wide.width, wide.height) == ImageProcessing.maxPixelSize)
        let square = try #require(ImageProcessing.crop(png, to: .square))
        #expect(square.mime == "image/jpeg" && square.width == 300 && square.height == 300)
        #expect(ImageProcessing.prepareForUpload(Data("pas une image".utf8)) == nil)
    }

    @Test("dossier des fichiers : écrire, relire, refuser ../, purger ce qui n'est plus cité")
    func store() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ave-media-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileMediaStore(directory: dir)
        let kept = try #require(store.save(Data([1]), fileName: "a/b:c.txt"))
        let dropped = try #require(store.save(Data([2]), fileName: "x.pdf"))
        #expect(kept.hasSuffix("/a-b-c.txt"))
        #expect(store.data(for: kept) == Data([1]))
        #expect(store.url(for: "../\(kept)") == nil && store.url(for: "\(UUID().uuidString)/..") == nil)
        store.purge(keeping: [kept])
        #expect(store.data(for: kept) == Data([1]))
        #expect(store.data(for: dropped) == nil)
    }
}

@MainActor
@Suite("Fichiers et images : session")
struct MediaSessionTests {
    private func harness(_ server: FakeFilesServer) throws -> (Harness, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ave-media-\(UUID().uuidString)")
        let media = MediaServices(files: try client(server), store: FileMediaStore(directory: dir))
        return (try Harness(media: media), dir)
    }

    @Test("joindre un document puis le traduire : envoi HTTP, tâche WebSocket, résultat téléchargé et gardé")
    func translateDocument() async throws {
        let server = FakeFilesServer()
        server.reply("/v1/files", status: 201,
                     json: #"{"file_id":"f1","kind":"pdf","mime":"application/pdf","size":3,"expires_at":4000000000}"#)
        server.reply("/v1/files/f2", status: 200, data: Data("hello".utf8))
        let (h, dir) = try harness(server)
        defer { try? FileManager.default.removeItem(at: dir) }
        let t = try await h.open()
        let c = h.coordinator

        c.attachDocument(Data([1, 2, 3]), fileName: "contrat-bail.pdf")
        #expect(c.attachmentDrafts.count == 1)
        #expect(await eventually { await c.attachmentDrafts.isEmpty })
        let attachment = try #require(c.transcript.messages.last)
        #expect(attachment.media?.fileID == "f1" && attachment.role == .user)

        await c.transformDocument(messageID: attachment.id, action: .translate, targetLang: "eng")
        let sent = try #require(t.sentJSON.last { $0["type"] as? String == "document_transform" })
        #expect(sent["file_id"] as? String == "f1" && sent["target_lang"] as? String == "eng")
        let ref = try #require(sent["ref"] as? String)
        #expect(c.transcript.messages.contains { $0.role == .user && $0.text == "Traduire en anglais" })

        t.serverSend(#"{"type":"task_started","seq":1,"task_id":"t1","ref":"\#(ref)","kind":"document_transform","estimated_s":10}"#)
        t.serverSend(#"{"type":"task_done","seq":2,"task_id":"t1","ref":"\#(ref)","kind":"document_transform","file_id":"f2","file_kind":"text","mime":"text/plain","size":5,"expires_at":4000000000,"url":"/v1/files/f2","simulated":true}"#)
        #expect(await eventually { await c.transcript.messages.last?.media?.kind == .document })
        let result = try #require(c.transcript.messages.last?.media)
        #expect(result.title == "contrat-bail (anglais).txt" && result.simulated && result.origin == .generated)
        #expect(c.mediaURL(result).flatMap { try? Data(contentsOf: $0) } == Data("hello".utf8))
        #expect(c.transcript.messages.last?.task == nil)
    }

    @Test("retouche d'une photo jointe : rien ne part sans la case d'accord")
    func rightsRequired() async throws {
        let server = FakeFilesServer()
        server.reply("/v1/files", status: 201,
                     json: #"{"file_id":"p1","kind":"png","mime":"image/png","size":3,"expires_at":4000000000}"#)
        let (h, dir) = try harness(server)
        defer { try? FileManager.default.removeItem(at: dir) }
        let t = try await h.open()
        let c = h.coordinator

        await c.attachImage(try makePNG(width: 64, height: 48), fileName: "IMG_1.png")
        #expect(await eventually { await c.transcript.messages.last?.media?.fileID == "p1" })
        let photo = try #require(c.transcript.messages.last)

        await c.editImage(messageID: photo.id, instruction: "fond flou", rightsConfirmed: false)
        #expect(!t.sentJSON.contains { $0["type"] as? String == "image_edit" })
        #expect(c.notice == UserMessages.mediaError(code: "rights_not_confirmed"))

        await c.editImage(messageID: photo.id, instruction: "fond flou", rightsConfirmed: true)
        let sent = try #require(t.sentJSON.last { $0["type"] as? String == "image_edit" })
        #expect(sent["rights_confirmed"] as? Bool == true && sent["file_id"] as? String == "p1")
    }

    @Test("annuler avant task_started : l'annulation part dès que le moteur annonce la tâche")
    func cancelEarly() async throws {
        let (h, dir) = try harness(FakeFilesServer())
        defer { try? FileManager.default.removeItem(at: dir) }
        let t = try await h.open()
        let c = h.coordinator
        await c.createImage(prompt: "Un marché au lever du soleil", size: .square, quality: .hd)
        let sent = try #require(t.sentJSON.last { $0["type"] as? String == "image_generate" })
        let ref = try #require(sent["ref"] as? String)
        let card = try #require(c.transcript.messages.last)
        await c.cancelTask(messageID: card.id)
        #expect(c.transcript.message(card.id)?.task?.state == .cancelled)
        t.serverSend(#"{"type":"task_started","seq":1,"task_id":"t7","ref":"\#(ref)","kind":"image_generate","estimated_s":35}"#)
        #expect(await eventually { t.sentJSON.contains { $0["type"] as? String == "task_cancel" && $0["task_id"] as? String == "t7" } })
    }

    @Test("signaler : l'image est masquée ; « merci » seulement si le moteur a gardé le signalement")
    func report() async throws {
        let server = FakeFilesServer()
        server.reply("/v1/reports", status: 503, json: #"{"error":"reports_disabled"}"#)
        let (h, dir) = try harness(server)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await h.open()
        let c = h.coordinator
        let id = c.transcript.appendAttachment(MediaItem(kind: .image, origin: .generated, title: "AVE.png", localName: nil,
                                                         mime: "image/png", byteCount: 1, fileID: "f9", expiresAt: 4_000_000_000))
        await c.report(messageID: id, reason: .misleading, note: nil)
        #expect(c.transcript.message(id)?.media?.hidden == true)
        #expect(c.notice == UserMessages.reportDisabled)
        server.reply("/v1/reports", status: 202, json: #"{"report_id":"r1"}"#)
        await c.report(messageID: id, reason: .misleading, note: nil)
        #expect(c.notice == UserMessages.reportSent)
    }

    @Test("session perdue pendant une tâche : le résultat est repris par HTTP ; une demande non annoncée est perdue")
    func recoveryAfterSessionLoss() async throws {
        let server = FakeFilesServer()
        server.reply("/v1/tasks/t1", status: 200, json: #"{"task_id":"t1","ref":"r","kind":"image_generate","state":"running"}"#)
        server.reply("/v1/files/f9", status: 200, data: try makePNG(width: 32, height: 32))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ave-media-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let h = try Harness(media: MediaServices(files: try client(server), store: FileMediaStore(directory: dir))) {
            $0.taskPollInterval = .milliseconds(20)
            $0.taskRequestSpacing = .milliseconds(1)
        }
        let c = h.coordinator
        let t0 = try await h.open()
        await c.createImage(prompt: "Un marché", size: .square, quality: .hd)
        await c.createImage(prompt: "Une plage", size: .square, quality: .hd)
        let refs = t0.sentJSON.filter { $0["type"] as? String == "image_generate" }.compactMap { $0["ref"] as? String }
        #expect(refs.count == 2)
        let started = try #require(refs.first)
        t0.serverSend(#"{"type":"task_started","seq":1,"task_id":"t1","ref":"\#(started)","kind":"image_generate","estimated_s":35}"#)
        let cards = c.transcript.messages.filter { $0.task != nil }.map(\.id)
        let first = try #require(cards.first)
        let second = try #require(cards.last)
        #expect(await eventually { await c.transcript.message(first)?.task?.taskID == "t1" })

        // La session expire : le moteur en ouvre une nouvelle, sans les événements de l'ancienne.
        t0.serverDrop()
        let t1 = try #require(await h.factory.waitForTransport(1))
        t1.serverReady(session: "autre", resumed: false)
        #expect(await eventually { await c.transcript.message(second)?.task?.state == .failed(code: "connection_lost", retryAfterSeconds: nil) })
        #expect(await eventually { server.requests.contains { $0.url?.path == "/v1/tasks/t1" } })
        #expect(c.transcript.message(first)?.task?.detached == true)

        server.reply("/v1/tasks/t1", status: 200, json: #"{"task_id":"t1","ref":"r","kind":"image_generate","state":"done","file_id":"f9","file_kind":"png","mime":"image/png","size":100,"expires_at":4000000000,"url":"/v1/files/f9","simulated":true,"width":32,"height":32}"#)
        #expect(await eventually { await c.transcript.message(first)?.media?.kind == .image })
        #expect(c.transcript.message(first)?.media?.simulated == true)
        #expect(c.transcript.message(first)?.task == nil)
        await c.stop()
    }

    @Test("hors ligne : la demande n'est pas mise en file, la carte propose de réessayer")
    func offline() async throws {
        let (h, dir) = try harness(FakeFilesServer())
        defer { try? FileManager.default.removeItem(at: dir) }
        let c = h.coordinator
        await c.createImage(prompt: "x", size: .square, quality: .hd)  // session jamais ouverte
        #expect(c.transcript.messages.last?.task?.state == .failed(code: "network", retryAfterSeconds: nil))
    }
}

@Suite("Créer une image dans la conversation (maquette validée le 2026-10-24)")
struct ImageInConversationTests {
    @Test("légende sous la description : format et qualité, défauts du moteur ; rien pour une autre tâche")
    func caption() {
        #expect(MediaTaskText.imageCaption(for: .imageGenerate(prompt: "Un marché", size: .landscape, quality: .hd, ref: "r1"))
                == "Image · Paysage · 1080p")
        #expect(MediaTaskText.imageCaption(for: .imageGenerate(prompt: "Une affiche", size: .portrait, quality: .uhd, ref: ""))
                == "Image · Portrait · 4K")
        #expect(MediaTaskText.imageCaption(for: .imageGenerate(prompt: "x", size: nil, quality: nil, ref: "")) == "Image · Carré · 1080p")
        #expect(MediaTaskText.imageCaption(for: .imageUpscale(fileID: "f", target: .uhd, rightsConfirmed: nil, ref: "")) == nil)
    }

    @Test("« Créer comme image » : seulement une phrase qui COMMENCE comme une demande d'image, avec une description")
    func intent() {
        for text in ["Crée une image d'un marché au lever du soleil", "crée-moi une image de plage", "Dessine un baobab",
                     "Peux-tu créer une image d’un lion", "  GÉNÈRE UNE IMAGE de Conakry la nuit", "Une image de pirogue"] {
            #expect(ImageIntent.suggestsImage(text), "\(text)")
        }
        for text in ["", "Crée une image", "Dessine", "Explique-moi cette image", "Que représente une image de satellite ?",
                     "Écris une lettre à la mairie", "Créer un compte"] {
            #expect(!ImageIntent.suggestsImage(text), "\(text)")
        }
    }
    /// Vecteurs « D12, … » du contrat (moteur `main` @ `fc40050`, PR #38).
    @Test("D12 : ready.engine.image_from_chat et task_started avec la description du modèle")
    func d12Decoding() throws {
        let ready = try ServerFrame.decode(#"{"type":"ready","session_id":"s","resumed":false,"last_mic_seq":0,"seq":0,"protocol":1,"engine":{"dialogue":"real","voice":"real","images":"real","documents":"real","image_tasks":["image_generate","image_edit","image_upscale","image_extend"],"image_from_chat":true}}"#)
        guard case .ready(let r) = ready.event else { Issue.record("pas ready"); return }
        #expect(r.engine?.createsImagesFromChat == true)
        let withoutGenerate = EngineStatus(dialogue: .real, voice: .real, images: .real, documents: .real,
                                           imageTasks: [.upscale], imageFromChat: true)
        #expect(!withoutGenerate.createsImagesFromChat)

        let started = try ServerFrame.decode(#"{"type":"task_started","seq":41,"task_id":"t_77","ref":"chat:5","kind":"image_generate","estimated_s":35,"prompt":"Un marché coloré au lever du soleil, étals de fruits, lumière dorée, photo réaliste","size":"square","quality":"1080p"}"#)
        #expect(started.event == .taskStarted(MediaTaskStarted(
            taskID: "t_77", ref: "chat:5", kind: .imageGenerate, estimatedSeconds: 35,
            prompt: "Un marché coloré au lever du soleil, étals de fruits, lumière dorée, photo réaliste",
            size: .square, quality: .hd)))
    }

    @Test("D12 : la tâche lancée par le moteur devient une carte ; un rejeu ne la double pas ; un ref inconnu est ignoré")
    func d12Card() {
        var t = ChatTranscript()
        let now = Date(timeIntervalSince1970: 1000)
        let started = MediaTaskStarted(taskID: "t_77", ref: "chat:5", kind: .imageGenerate, estimatedSeconds: 35,
                                       prompt: "Un marché coloré", size: .landscape, quality: .hd)
        t.applyTask(.taskStarted(started), now: now)
        #expect(t.messages.count == 1)
        let card = t.messages.last?.task
        #expect(card?.isFromChat == true && card?.taskID == "t_77")
        #expect(card?.state == .working(startedAt: now, estimatedSeconds: 35))
        #expect(card?.request == .imageGenerate(prompt: "Un marché coloré", size: .landscape, quality: .hd, ref: "chat:5"))
        t.applyTask(.taskStarted(started), now: now)  // rejeu à la reprise de session
        #expect(t.messages.count == 1)
        t.applyTask(.taskStarted(MediaTaskStarted(taskID: "t_9", ref: "r_perdu", kind: .imageGenerate, estimatedSeconds: 30)))
        t.applyTask(.taskStarted(MediaTaskStarted(taskID: "t_10", ref: "chat:6", kind: .documentTransform, estimatedSeconds: 5)))
        #expect(t.messages.count == 1)
        // La phrase du tour 5 arrive après la carte : elle passe devant, la carte reste en cours après la fin du tour.
        t.apply(.replyText(utteranceID: 5, text: "Je m'occupe de te créer cette image.\n\n", lang: "fra"))
        t.apply(.turnEnd(utteranceID: 5, interrupted: false))
        #expect(t.messages.map { $0.task == nil } == [true, false])
        #expect(t.messages.last?.task?.state == .working(startedAt: now, estimatedSeconds: 35))
    }
}
