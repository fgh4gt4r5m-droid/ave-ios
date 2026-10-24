import AVECore
import Foundation

/// Ce dont la session a besoin pour les fichiers : les routes HTTP du moteur et le dossier des fichiers sur l'iPhone.
public struct MediaServices: Sendable {
    public let files: AVEFilesClient
    public let store: any MediaStore

    public init(files: AVEFilesClient, store: any MediaStore) {
        self.files = files
        self.store = store
    }
}

/// Fichiers, documents et images (E16, E17 ; maquette validée le 2026-10-23). Les demandes partent dans la session
/// WebSocket ; les fichiers passent en HTTP. Rien ne part sans un geste explicite de la personne.
extension SessionCoordinator {
    public var supportsMedia: Bool { media != nil }
    /// D11 : tâche d'image proposée par le moteur dans cette session (toutes avant le premier `ready` ou avec un moteur
    /// antérieur ; une tâche coupée répondrait de toute façon `feature_disabled`).
    public func offers(_ task: EngineStatus.ImageTask) -> Bool { supportsMedia && (engine?.offers(task) ?? true) }

    public func mediaURL(_ item: MediaItem) -> URL? {
        item.localName.flatMap(mediaURL(named:))
    }

    public func mediaURL(named name: String) -> URL? {
        media?.store.url(for: name)
    }

    /// Fichier refusé avant tout envoi (trop lourd, illisible) : il apparaît dans le fil avec son message d'erreur.
    public func rejectAttachment(fileName: String, byteCount: Int, kind: MediaItem.Kind, code: String) {
        transcript.appendAttachment(failedAttachment(kind, title: fileName, byteCount: byteCount, code: code))
    }

    // MARK: Joindre

    /// Joint une photo : convertie en JPEG si besoin (HEIC, trop lourde), gardée sur l'iPhone, puis envoyée au moteur.
    public func attachImage(_ data: Data, fileName: String) async {
        guard let media else {
            notice = UserMessages.mediaUnavailable
            return
        }
        // Décodage et réencodage d'une photo de 12 Mpx : hors de l'acteur principal, l'écran reste fluide.
        let prepared = await Task.detached(priority: .userInitiated) { ImageProcessing.prepareForUpload(data) }.value
        guard let prepared else {
            transcript.appendAttachment(failedAttachment(.image, title: fileName, byteCount: data.count,
                                                         code: data.count > MediaLimits.maxUploadBytes ? "file_too_large" : "image_unreadable"))
            return
        }
        let ext = prepared.mime == "image/png" ? "png" : "jpg"
        let stem = (fileName as NSString).deletingPathExtension
        let title = "\(stem.isEmpty ? "Photo" : stem).\(ext)"
        guard let name = media.store.save(prepared.data, fileName: title) else {
            transcript.appendAttachment(failedAttachment(.image, title: title, byteCount: prepared.data.count, code: "file_missing"))
            return
        }
        let item = MediaItem(kind: .image, origin: .attachment, title: title, localName: name, mime: prepared.mime,
                             byteCount: prepared.data.count, width: prepared.width, height: prepared.height)
        startUpload(item, data: prepared.data)
    }

    /// Joint un document (PDF, Word, texte) tel quel : le moteur reconnaît le type au contenu.
    public func attachDocument(_ data: Data, fileName: String) {
        guard let media else {
            notice = UserMessages.mediaUnavailable
            return
        }
        let mime = Self.documentMime(for: fileName)
        guard data.count <= MediaLimits.maxUploadBytes else {
            transcript.appendAttachment(failedAttachment(.document, title: fileName, byteCount: data.count, code: "file_too_large"))
            return
        }
        guard let name = media.store.save(data, fileName: fileName) else {
            transcript.appendAttachment(failedAttachment(.document, title: fileName, byteCount: data.count, code: "file_missing"))
            return
        }
        startUpload(MediaItem(kind: .document, origin: .attachment, title: fileName, localName: name, mime: mime,
                              byteCount: data.count), data: data)
    }

    /// La croix de la pièce jointe dans la barre : l'envoi est abandonné.
    public func cancelAttachment(_ id: UUID) {
        uploadTasks[id]?.cancel()
        uploadTasks[id] = nil
        attachmentDrafts.removeAll { $0.id == id }
    }

    // MARK: Demandes

    /// « Créer une image » : la description est la bulle de la personne.
    public func createImage(prompt: String, size: ImageSize, quality: ImageQuality) async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.count <= MediaTaskRequest.promptMaxCharacters else {
            notice = UserMessages.mediaError(code: "prompt_too_long")
            return
        }
        await submit(.imageGenerate(prompt: text, size: size, quality: quality, ref: ""), sourceMessageID: nil,
                     userLabel: text, resultTitle: "Image")
    }

    /// Traduire, résumer, reformuler un document joint.
    public func transformDocument(messageID: Int, action: DocumentAction, targetLang: String? = nil,
                                  instruction: String? = nil) async {
        guard let item = transcript.message(messageID)?.media, item.kind == .document else { return }
        let lang = action == .translate ? (targetLang == "fra" ? "fra" : "eng") : nil
        let note = instruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        await submit(.documentTransform(fileID: "", action: action, targetLang: lang,
                                        instruction: (note?.isEmpty ?? true) ? nil : note, ref: ""),
                     sourceMessageID: messageID,
                     userLabel: MediaTaskText.userLabel(action: action, targetLang: lang, instruction: note),
                     resultTitle: MediaTaskText.documentResultTitle(source: item.title, action: action, targetLang: lang))
    }

    /// « Modifier… » : retouche d'après une consigne. `rightsConfirmed` : la personne a coché la case d'accord.
    public func editImage(messageID: Int, instruction: String, rightsConfirmed: Bool) async {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, case .allowed(let flag) = rights(for: messageID, confirmed: rightsConfirmed) else { return }
        await submit(.imageEdit(fileID: "", instruction: text, quality: nil, rightsConfirmed: flag, ref: ""),
                     sourceMessageID: messageID, userLabel: "Modifier : \(text)", resultTitle: "Image")
    }

    /// « Agrandir » en 1080p ou en 4K (le moteur garde les proportions).
    public func upscaleImage(messageID: Int, target: ImageQuality, rightsConfirmed: Bool) async {
        guard case .allowed(let flag) = rights(for: messageID, confirmed: rightsConfirmed) else { return }
        await submit(.imageUpscale(fileID: "", target: target, rightsConfirmed: flag, ref: ""),
                     sourceMessageID: messageID, userLabel: target == .uhd ? "Agrandir en 4K" : "Agrandir en 1080p",
                     resultTitle: "Image")
    }

    /// « Prolonger » vers un autre format : l'IA invente les bords.
    public func extendImage(messageID: Int, aspect: ImageSize, rightsConfirmed: Bool) async {
        guard case .allowed(let flag) = rights(for: messageID, confirmed: rightsConfirmed) else { return }
        await submit(.imageExtend(fileID: "", aspect: aspect, quality: nil, rightsConfirmed: flag, ref: ""),
                     sourceMessageID: messageID, userLabel: "Prolonger en \(Self.aspectName(aspect))", resultTitle: "Image")
    }

    /// « Recadrer » : sur l'iPhone, sans IA ni envoi ; la photo recadrée devient une nouvelle pièce jointe (envoyée
    /// seulement si une tâche la demande ensuite).
    public func cropImage(messageID: Int, aspect: ImageSize) async {
        guard let media, let item = transcript.message(messageID)?.media, item.kind == .image else { return }
        guard let data = item.localName.flatMap({ media.store.data(for: $0) }) else {
            notice = UserMessages.mediaError(code: "file_missing")
            return
        }
        let cropped = await Task.detached(priority: .userInitiated) { ImageProcessing.crop(data, to: aspect) }.value
        guard let cropped else {
            notice = UserMessages.mediaError(code: "image_unreadable")
            return
        }
        let stem = (item.title as NSString).deletingPathExtension
        let title = "\(stem) (\(Self.aspectName(aspect))).jpg"
        guard let name = media.store.save(cropped.data, fileName: title) else {
            notice = UserMessages.mediaError(code: "file_missing")
            return
        }
        // Une photo recadrée reste la photo de la personne : même origine, même accord éventuel.
        transcript.appendAttachment(MediaItem(kind: .image, origin: item.origin == .generated ? .attachment : item.origin,
                                              title: title, localName: name, mime: cropped.mime,
                                              byteCount: cropped.data.count, width: cropped.width, height: cropped.height,
                                              rightsConfirmed: item.rightsConfirmed))
    }

    /// « Refaire » sous une image créée d'après une description : la même demande, une nouvelle image.
    public func redo(messageID: Int) async {
        guard let request = transcript.message(messageID)?.media?.request, case .imageGenerate = request else { return }
        await submit(request, sourceMessageID: nil, userLabel: nil, resultTitle: "Image")
    }

    public func canRedo(messageID: Int) -> Bool {
        guard let request = transcript.message(messageID)?.media?.request, case .imageGenerate = request else { return false }
        return offers(.generate)
    }

    /// « Annuler » sur la carte. Avant `task_started`, l'annulation est locale ; elle est transmise au moteur dès qu'il
    /// annonce la tâche (pour ne pas faire tourner le GPU pour rien).
    public func cancelTask(messageID: Int) async {
        guard let card = transcript.message(messageID)?.task, card.canCancel else { return }
        if let taskID = card.taskID {
            if !(await client.cancelTask(taskID: taskID)) { notice = UserMessages.notConnected }
            // La carte passe à « annulée » au `task_error cancelled` du moteur.
        } else {
            transcript.updateTask(messageID: messageID) { $0.state = .cancelled }
        }
    }

    /// « Réessayer » sur une carte échouée : le téléchargement seul si le résultat existe encore, sinon la demande.
    public func retryTask(messageID: Int) async {
        guard let card = transcript.message(messageID)?.task, card.isFinished else { return }
        if case .failed(let code, _) = card.state, code == "download_failed", let result = card.pendingResult,
           Double(result.expiresAt) > Date().timeIntervalSince1970 {
            transcript.updateTask(messageID: messageID) { $0.state = .downloading }
            download(result, messageID: messageID)
            return
        }
        let ref = Self.newRef()
        transcript.updateTask(messageID: messageID) {
            $0.ref = ref
            $0.request = $0.request.replacing(ref: ref)
            $0.taskID = nil
            $0.pendingResult = nil
            $0.detached = false
            $0.state = .sending
        }
        await send(cardID: messageID)
    }

    // MARK: Signaler (E17)

    /// Masque l'image tout de suite, puis signale. Le message dit honnêtement si le moteur a gardé le signalement.
    public func report(messageID: Int, reason: ReportReason, note: String?) async {
        guard let item = transcript.message(messageID)?.media else { return }
        transcript.updateMedia(messageID: messageID) { $0.hidden = true }
        guard let media, let fileID = item.fileID else {
            notice = UserMessages.reportDisabled
            return
        }
        do {
            _ = try await media.files.report(fileID: fileID, taskID: item.taskID, reason: reason, note: note)
            notice = UserMessages.reportSent
        } catch MediaFileError.reportsDisabled {
            notice = UserMessages.reportDisabled
        } catch {
            notice = UserMessages.reportFailed
        }
    }

    // MARK: Événements du moteur

    func handleTask(_ event: ServerEvent) {
        // Annulée avant que le moteur ne l'annonce : on la lui fait arrêter maintenant.
        if case .taskStarted(let started) = event, let id = transcript.messageID(forTaskRef: started.ref),
           transcript.message(id)?.task?.state == .cancelled {
            Task { await client.cancelTask(taskID: started.taskID) }
            return
        }
        guard let done = transcript.applyTask(event) else { return }
        download(done.result, messageID: done.messageID)
    }

    // MARK: Reprise après une session perdue (D1)

    /// Nouvelle session (l'ancienne a expiré) : les tâches en cours continuent sur le moteur, mais leurs événements
    /// sont perdus. Celles qui ont démarré sont suivies par HTTP ; une demande pas encore annoncée est perdue.
    func detachTasksAfterSessionLoss() {
        for message in transcript.messages {
            guard let card = message.task else { continue }
            switch card.state {
            case .sending:
                transcript.updateTask(messageID: message.id) {
                    $0.state = .failed(code: "connection_lost", retryAfterSeconds: nil)
                }
            case .working where card.taskID != nil:
                transcript.updateTask(messageID: message.id) { $0.detached = true }
            default:
                break
            }
        }
        startTaskRecovery()
    }

    private var detachedTasks: [(messageID: Int, taskID: String)] {
        transcript.messages.compactMap { message in
            guard let card = message.task, card.detached, case .working = card.state, let taskID = card.taskID
            else { return nil }
            return (message.id, taskID)
        }
    }

    private func startTaskRecovery() {
        guard taskRecovery == nil, media != nil, !detachedTasks.isEmpty else { return }
        taskRecovery = Task { [weak self] in
            await self?.runTaskRecovery()
            self?.taskRecovery = nil
        }
    }

    /// Tant qu'une carte attend : une requête par tâche, espacées (limite du moteur), puis une pause. S'arrête de lui-même
    /// au résultat, à l'échec, ou au bout d'1 h (le moteur répond alors `task_not_found`).
    private func runTaskRecovery() async {
        while !Task.isCancelled {
            let pending = detachedTasks
            if pending.isEmpty { return }
            for task in pending {
                if Task.isCancelled { return }
                await checkTask(messageID: task.messageID, taskID: task.taskID)
                try? await Task.sleep(for: configuration.taskRequestSpacing)
            }
            try? await Task.sleep(for: configuration.taskPollInterval)
        }
    }

    private func checkTask(messageID: Int, taskID: String) async {
        guard let media else { return }
        let status: MediaTaskStatus?
        do {
            status = try await media.files.taskStatus(taskID: taskID)
        } catch MediaFileError.notFound {
            status = nil
        } catch {
            return  // réseau, limite du moteur : on réessaie au tour suivant
        }
        // La carte a pu changer pendant la requête (annulée, refaite).
        guard let card = transcript.message(messageID)?.task, card.taskID == taskID, card.detached,
              case .working = card.state else { return }
        switch status {
        case nil:
            transcript.updateTask(messageID: messageID) { $0.state = .failed(code: "task_expired", retryAfterSeconds: nil) }
        case .running:
            break
        case .done(let result):
            transcript.updateTask(messageID: messageID) {
                $0.state = .downloading
                $0.pendingResult = result
            }
            download(result, messageID: messageID)
        case .failed(let code):
            transcript.updateTask(messageID: messageID) {
                $0.state = code == "cancelled" ? .cancelled : .failed(code: code, retryAfterSeconds: nil)
            }
        }
    }

    // MARK: Interne

    private func submit(_ request: MediaTaskRequest, sourceMessageID: Int?, userLabel: String?, resultTitle: String) async {
        guard media != nil else {
            notice = UserMessages.mediaUnavailable
            return
        }
        if let userLabel { transcript.appendUserRequest(userLabel) }
        let ref = Self.newRef()
        let cardID = transcript.appendTask(MediaTaskCard(ref: ref, request: request.replacing(ref: ref),
                                                         sourceMessageID: sourceMessageID, resultTitle: resultTitle))
        await send(cardID: cardID)
    }

    /// Renvoie le fichier source s'il a expiré, puis envoie la demande. Une demande n'attend pas le réseau : hors ligne,
    /// la carte le dit et propose « Réessayer ».
    private func send(cardID: Int) async {
        guard var request = transcript.message(cardID)?.task?.request else { return }
        if let source = transcript.message(cardID)?.task?.sourceMessageID {
            let fileID: String
            switch await ensureFileID(messageID: source) {
            case .success(let id): fileID = id
            case .failure(let error):
                transcript.updateTask(messageID: cardID) {
                    $0.state = .failed(code: error.code, retryAfterSeconds: error.retryAfterSeconds)
                }
                return
            }
            request = request.replacing(fileID: fileID, ref: request.ref)
        }
        // L'utilisateur a pu annuler pendant le renvoi du fichier.
        guard transcript.message(cardID)?.task?.state == .sending else { return }
        transcript.updateTask(messageID: cardID) { $0.request = request }
        if !(await client.sendTask(request)) {
            transcript.updateTask(messageID: cardID) { $0.state = .failed(code: "network", retryAfterSeconds: nil) }
        }
    }

    /// `file_id` valable du fichier de ce message, en le renvoyant depuis l'iPhone si le moteur l'a oublié.
    private func ensureFileID(messageID: Int) async -> Result<String, MediaFileError> {
        guard let media, let item = transcript.message(messageID)?.media else { return .failure(.notFound) }
        if item.hasValidFileID(), let fileID = item.fileID { return .success(fileID) }
        guard let data = item.localName.flatMap({ media.store.data(for: $0) }) else { return .failure(.notFound) }
        do {
            let uploaded = try await media.files.upload(data, idempotencyKey: UUID().uuidString)
            transcript.updateMedia(messageID: messageID) {
                $0.fileID = uploaded.fileID
                $0.expiresAt = uploaded.expiresAt
                $0.state = .ready
            }
            return .success(uploaded.fileID)
        } catch let error as MediaFileError {
            return .failure(error)
        } catch {
            return .failure(.network)
        }
    }

    private func startUpload(_ item: MediaItem, data: Data) {
        guard let media else { return }
        let draft = AttachmentDraft(id: UUID(), title: item.title, kind: item.kind, byteCount: item.byteCount,
                                    localName: item.localName)
        attachmentDrafts.append(draft)
        let files = media.files
        uploadTasks[draft.id] = Task { [weak self] in
            let outcome: Result<UploadedFile, MediaFileError>
            do {
                // Clé d'idempotence = la pièce jointe : un nouvel essai sur un réseau instable ne crée pas de doublon.
                outcome = .success(try await files.upload(data, idempotencyKey: draft.id.uuidString))
            } catch let error as MediaFileError {
                outcome = .failure(error)
            } catch {
                outcome = .failure(.network)
            }
            guard !Task.isCancelled else { return }
            self?.finishUpload(draft: draft, item: item, outcome: outcome)
        }
    }

    private func finishUpload(draft: AttachmentDraft, item: MediaItem, outcome: Result<UploadedFile, MediaFileError>) {
        uploadTasks[draft.id] = nil
        guard attachmentDrafts.contains(where: { $0.id == draft.id }) else { return }  // enlevée entre-temps
        attachmentDrafts.removeAll { $0.id == draft.id }
        var item = item
        switch outcome {
        case .success(let uploaded):
            item.fileID = uploaded.fileID
            item.expiresAt = uploaded.expiresAt
        case .failure(let error):
            item.state = .failed(code: error.code)
        }
        transcript.appendAttachment(item)
    }

    private func download(_ result: MediaTaskResult, messageID: Int) {
        guard let media else { return }
        let files = media.files
        Task { [weak self] in
            let data = try? await files.download(path: result.url)
            self?.finishDownload(data, result: result, messageID: messageID)
        }
    }

    private func finishDownload(_ data: Data?, result: MediaTaskResult, messageID: Int) {
        guard let media, let card = transcript.message(messageID)?.task, card.state == .downloading,
              card.pendingResult == result else { return }
        let isImage = result.mime.lowercased().hasPrefix("image/")
        let title = isImage ? MediaTaskText.imageResultTitle(mime: result.mime) : card.resultTitle
        guard let data, let name = media.store.save(data, fileName: title) else {
            transcript.updateTask(messageID: messageID) { $0.state = .failed(code: "download_failed", retryAfterSeconds: nil) }
            return
        }
        let size = isImage ? ImageProcessing.dimensions(of: data) : nil
        let item = MediaItem(kind: isImage ? .image : .document, origin: .generated, title: title, localName: name,
                             mime: result.mime, byteCount: data.count, width: result.width ?? size?.width,
                             height: result.height ?? size?.height, fileID: result.fileID, expiresAt: result.expiresAt,
                             simulated: result.simulated, taskID: result.taskID, request: card.request)
        transcript.completeTask(messageID: messageID, with: item)
    }

    enum RightsDecision: Equatable {
        /// `rights_confirmed` à envoyer : `true` quand le moteur verra une photo envoyée, absent pour une image d'AVE.
        case allowed(Bool?)
        /// Case non cochée (ou pas une image) : rien ne part.
        case refused
    }

    private func rights(for messageID: Int, confirmed: Bool) -> RightsDecision {
        guard let item = transcript.message(messageID)?.media, item.kind == .image else { return .refused }
        guard item.requiresRightsForTask() else { return .allowed(nil) }
        guard confirmed || item.rightsConfirmed else {
            notice = UserMessages.mediaError(code: "rights_not_confirmed")
            return .refused
        }
        transcript.updateMedia(messageID: messageID) { $0.rightsConfirmed = true }
        return .allowed(true)
    }

    private func failedAttachment(_ kind: MediaItem.Kind, title: String, byteCount: Int, code: String) -> MediaItem {
        MediaItem(kind: kind, origin: .attachment, title: title, localName: nil,
                  mime: kind == .image ? "image/jpeg" : Self.documentMime(for: title), byteCount: byteCount,
                  state: .failed(code: code))
    }

    static func newRef() -> String { UUID().uuidString.lowercased() }

    static func aspectName(_ aspect: ImageSize) -> String {
        switch aspect {
        case .square: return "carré"
        case .portrait: return "portrait"
        case .landscape: return "paysage"
        }
    }

    /// Indication seulement : le moteur reconnaît le vrai type au contenu.
    static func documentMime(for fileName: String) -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "text/plain"
        }
    }
}
