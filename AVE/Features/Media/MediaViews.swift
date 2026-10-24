#if os(iOS)
import AVECore
import Photos
import QuickLook
import SwiftUI

/// Feuilles des fichiers et images, ouvertes par la conversation (`ChatView`).
enum MediaSheet: Identifiable, Equatable {
    case edit(messageID: Int)
    /// Agrandir ou prolonger une photo jointe : la case d'accord d'abord.
    case rights(messageID: Int, action: RightsAction)
    case rewrite(messageID: Int)
    case report(messageID: Int)

    enum RightsAction: Equatable {
        case upscale(ImageQuality)
        case extend(ImageSize)
    }

    var id: String {
        switch self {
        case .edit(let id): return "edit-\(id)"
        case .rights(let id, _): return "rights-\(id)"
        case .rewrite(let id): return "rewrite-\(id)"
        case .report(let id): return "report-\(id)"
        }
    }
}

// MARK: Pièce jointe en cours d'envoi (barre de saisie)

struct AttachmentDraftRow: View {
    let draft: AttachmentDraft
    let url: URL?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if draft.kind == .image {
                    MediaThumbnail(url: url, maxPixelSize: 120)
                        .frame(width: 40, height: 40)
                        .clipShape(.rect(cornerRadius: 8))
                } else {
                    DocumentIcon(title: draft.title).frame(width: 40, height: 40)
                }
                ProgressView().controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(draft.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("Envoi… \(MediaFormat.size(draft.byteCount))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Enlever la pièce jointe", systemImage: "xmark", action: onRemove)
                .labelStyle(.iconOnly)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.leading, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Envoi de \(draft.title), \(MediaFormat.size(draft.byteCount))")
    }
}

// MARK: Message avec un fichier ou une tâche

/// Un message de la conversation qui porte une pièce jointe, une carte de tâche ou un résultat.
struct MediaMessageView: View {
    let message: ChatMessage
    let coordinator: SessionCoordinator
    /// Dernière pièce jointe du fil : ses actions sont montrées en raccourcis (sinon par appui long).
    let showsActions: Bool
    let onSheet: (MediaSheet) -> Void

    var body: some View {
        if let task = message.task {
            TaskCardView(card: task,
                         onCancel: { Task { await coordinator.cancelTask(messageID: message.id) } },
                         onRetry: { Task { await coordinator.retryTask(messageID: message.id) } })
        } else if let media = message.media {
            if message.role == .user {
                VStack(alignment: .trailing, spacing: 10) {
                    AttachmentBubble(media: media, url: coordinator.mediaURL(media))
                        .contextMenu { if media.state == .ready { actionsMenu(media) } }
                    if showsActions, media.state == .ready, coordinator.supportsMedia {
                        AttachmentActions(media: media, offered: Set(EngineStatus.ImageTask.allCases.filter { coordinator.offers($0) }),
                                          onAction: perform)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else if media.kind == .image {
                ImageResultView(media: media, url: coordinator.mediaURL(media),
                                canRedo: coordinator.canRedo(messageID: message.id),
                                onRedo: { Task { await coordinator.redo(messageID: message.id) } },
                                onReport: { onSheet(.report(messageID: message.id)) },
                                moreMenu: { actionsMenu(media) })
            } else {
                DocumentResultView(media: media, url: coordinator.mediaURL(media))
            }
        }
    }

    /// Les mêmes actions qu'en raccourcis, dans le menu d'appui long (ou « Plus » sous une image produite).
    @ViewBuilder private func actionsMenu(_ media: MediaItem) -> some View {
        if media.kind == .image {
            Menu("Recadrer", systemImage: "crop") {
                ForEach(ImageSize.allCases, id: \.self) { size in
                    Button(MediaFormat.aspect(size)) { perform(.crop(size)) }
                }
            }
            // D11 : une tâche coupée par l'exploitant n'apparaît pas (recadrer se fait sur l'iPhone, toujours là).
            if coordinator.offers(.extend) {
                Menu("Prolonger", systemImage: "arrow.up.left.and.arrow.down.right") {
                    ForEach(ImageSize.allCases, id: \.self) { size in
                        Button("En \(MediaFormat.aspect(size).lowercased())") { perform(.extend(size)) }
                    }
                }
            }
            if coordinator.offers(.upscale) {
                Menu("Agrandir", systemImage: "sparkles") {
                    Button("En 1080p") { perform(.upscale(.hd)) }
                    Button("En 4K") { perform(.upscale(.uhd)) }
                }
            }
            if coordinator.offers(.edit) {
                Button("Modifier…", systemImage: "pencil") { perform(.edit) }
            }
        } else {
            Button("Traduire en anglais", systemImage: "character.bubble") { perform(.translate("eng")) }
            Button("Traduire en français", systemImage: "character.bubble") { perform(.translate("fra")) }
            Button("Résumer", systemImage: "text.badge.minus") { perform(.summarize) }
            Button("Reformuler…", systemImage: "text.redaction") { perform(.rewrite) }
        }
    }

    private func perform(_ action: AttachmentAction) {
        let id = message.id
        let needsRights = message.media.map { $0.requiresRightsForTask() && !$0.rightsConfirmed } ?? false
        switch action {
        case .crop(let size): Task { await coordinator.cropImage(messageID: id, aspect: size) }
        case .extend(let size):
            if needsRights { onSheet(.rights(messageID: id, action: .extend(size))) }
            else { Task { await coordinator.extendImage(messageID: id, aspect: size, rightsConfirmed: false) } }
        case .upscale(let target):
            if needsRights { onSheet(.rights(messageID: id, action: .upscale(target))) }
            else { Task { await coordinator.upscaleImage(messageID: id, target: target, rightsConfirmed: false) } }
        case .edit: onSheet(.edit(messageID: id))
        case .translate(let lang):
            Task { await coordinator.transformDocument(messageID: id, action: .translate, targetLang: lang) }
        case .summarize: Task { await coordinator.transformDocument(messageID: id, action: .summarize) }
        case .rewrite: onSheet(.rewrite(messageID: id))
        }
    }
}

enum AttachmentAction {
    case crop(ImageSize), extend(ImageSize), upscale(ImageQuality), edit
    case translate(String), summarize, rewrite
}

/// La pièce jointe de la personne, à droite comme ses messages.
struct AttachmentBubble: View {
    let media: MediaItem
    let url: URL?
    @State private var preview: URL?
    @Environment(\.aveTheme) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 10) {
                if media.kind == .image, url != nil {
                    // Un toucher sur la vignette : la photo en plein écran.
                    Button { preview = url } label: {
                        MediaThumbnail(url: url, maxPixelSize: 300)
                            .frame(width: 64, height: 64)
                            .clipShape(.rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                } else {
                    DocumentIcon(title: media.title).frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(MediaFormat.detail(media)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(theme.userBubble, in: .rect(cornerRadius: theme.cornerRadius))
            if case .failed(let code) = media.state {
                ErrorLine(text: UserMessages.mediaError(code: code))
            }
        }
        .padding(.leading, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vous avez joint \(media.title), \(MediaFormat.detail(media))")
        .quickLookPreview($preview)
    }
}

/// Raccourcis sous la dernière pièce jointe (maquettes 3 et 10).
struct AttachmentActions: View {
    let media: MediaItem
    /// D11 : tâches d'image proposées par le moteur (un ensemble plutôt qu'une fonction du coordinateur, isolé au MainActor).
    let offered: Set<EngineStatus.ImageTask>
    let onAction: (AttachmentAction) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(media.kind == .image ? "Que voulez-vous faire de cette photo ?" : "Que voulez-vous faire de ce document ?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            FlowChips {
                if media.kind == .image {
                    Menu { aspectButtons { onAction(.crop($0)) } } label: { chip("Recadrer", "crop") }
                    if offered.contains(.extend) {
                        Menu { aspectButtons { onAction(.extend($0)) } } label: {
                            chip("Prolonger", "arrow.up.left.and.arrow.down.right")
                        }
                    }
                    if offered.contains(.upscale) {
                        Menu {
                            Button("En 1080p") { onAction(.upscale(.hd)) }
                            Button("En 4K") { onAction(.upscale(.uhd)) }
                        } label: { chip("Agrandir", "sparkles") }
                    }
                    if offered.contains(.edit) {
                        Button { onAction(.edit) } label: { chip("Modifier…", "pencil") }
                    }
                } else {
                    Menu {
                        Button("En anglais") { onAction(.translate("eng")) }
                        Button("En français") { onAction(.translate("fra")) }
                    } label: { chip("Traduire", "character.bubble") }
                    Button { onAction(.summarize) } label: { chip("Résumer", "text.badge.minus") }
                    Button { onAction(.rewrite) } label: { chip("Reformuler…", "text.redaction") }
                }
            }
            if media.kind == .image {
                Text(UserMessages.cropIsLocal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func aspectButtons(_ action: @escaping (ImageSize) -> Void) -> some View {
        ForEach(ImageSize.allCases, id: \.self) { size in
            Button(MediaFormat.aspect(size)) { action(size) }
        }
    }

    private func chip(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemBackground), in: .capsule)
            .contentShape(.capsule)
    }
}

/// Raccourcis disposés sur plusieurs lignes, alignés à droite comme les bulles de la personne.
struct FlowChips<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        FlowLayout(spacing: 8) { content }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.maxX - row.width
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = current.indices.isEmpty ? size.width : size.width + spacing
            if !current.indices.isEmpty, current.width + extra > width {
                rows.append(current)
                current = Row()
            }
            current.width += current.indices.isEmpty ? size.width : size.width + spacing
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: Carte de tâche (maquette 5)

struct TaskCardView: View {
    let card: MediaTaskCard
    let onCancel: () -> Void
    let onRetry: () -> Void
    @Environment(\.aveTheme) private var theme

    var body: some View {
        switch card.state {
        case .cancelled:
            Label(UserMessages.mediaError(code: "cancelled"), systemImage: "xmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let code, let retry):
            VStack(alignment: .leading, spacing: 8) {
                ErrorLine(text: UserMessages.mediaError(code: code, retryAfterSeconds: retry))
                if Self.isRetryable(code) {
                    Button("Réessayer", systemImage: "arrow.clockwise", action: onRetry)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            working
        }
    }

    private var working: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AVELiveMark(phase: .thinking).frame(width: 32, height: 32).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    subtitle
                }
            }
            progress
            // D12 : ce que le modèle a décidé de dessiner (2 à 4 phrases), replié par défaut.
            if card.isFromChat, case .imageGenerate(let prompt, _, _, _) = card.request, !prompt.isEmpty {
                PromptPreview(text: prompt)
            }
            if card.canCancel {
                Button("Annuler", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.assistantBubble, in: .rect(cornerRadius: theme.cornerRadius))
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch card.state {
        case .sending: return "Envoi de la demande…"
        case .downloading: return "Réception du résultat…"
        default: return MediaTaskText.workingTitle(for: card.request)
        }
    }

    @ViewBuilder private var subtitle: some View {
        if case .working(let start, let estimate) = card.state, let text = MediaTaskText.estimate(estimate) {
            TimelineView(.periodic(from: start, by: 5)) { context in
                let late = context.date.timeIntervalSince(start) > Double(estimate ?? 0)
                Text(late ? "Un peu plus long que prévu…" : text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Avancée d'après l'ESTIMATION du moteur, plafonnée à 95 % : la barre ne prétend jamais que c'est fini.
    @ViewBuilder private var progress: some View {
        if case .working(let start, let estimate?) = card.state, estimate > 0 {
            TimelineView(.periodic(from: start, by: 1)) { context in
                ProgressView(value: min(context.date.timeIntervalSince(start) / Double(estimate), 0.95))
            }
            .accessibilityHidden(true)
        } else {
            ProgressView().progressViewStyle(.linear).accessibilityHidden(true)
        }
    }

    /// Réessayer n'a pas de sens après un refus de modération ou un fichier impossible à traiter.
    static func isRetryable(_ code: String) -> Bool {
        !["content_refused", "rights_not_confirmed", "feature_disabled", "unsupported_type", "file_too_large",
          "no_text", "language_unavailable"].contains(code)
    }
}

/// La description rédigée par le modèle (D12), sur deux lignes ; un toucher la montre en entier.
struct PromptPreview: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 2)
            Button(expanded ? "Réduire" : "Voir la description") { withAnimation(.snappy) { expanded.toggle() } }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: Résultats (maquettes 6 et 7)

struct ImageResultView<More: View>: View {
    let media: MediaItem
    let url: URL?
    let canRedo: Bool
    let onRedo: () -> Void
    let onReport: () -> Void
    @ViewBuilder let moreMenu: () -> More
    @State private var savedMessage: String?
    /// Aperçu plein écran du système (pincer pour zoomer, partager), comme une photo dans Messages.
    @State private var preview: URL?
    @Environment(\.aveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if media.hidden {
                Label("Image masquée après signalement.", systemImage: "eye.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.assistantBubble, in: .rect(cornerRadius: theme.cornerRadius))
            } else {
                Button { preview = url } label: {
                    MediaThumbnail(url: url, maxPixelSize: 1200)
                        .frame(maxWidth: 320)
                        .clipShape(.rect(cornerRadius: theme.cornerRadius))
                        .overlay(alignment: .topLeading) { badges }
                        .contentShape(.rect(cornerRadius: theme.cornerRadius))
                }
                .buttonStyle(.plain)
                .disabled(url == nil)
                .accessibilityLabel(media.simulated ? UserMessages.simulatedBadge : "Image créée par AVE")
                .accessibilityHint("Ouvre l'image en plein écran.")
                if media.simulated { InfoLine(text: UserMessages.simulatedImage) }
                actions
                if let savedMessage {
                    Text(savedMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .quickLookPreview($preview)
    }

    /// « Image de démonstration » tant que le moteur est factice. Plus d'étiquette « Générée par IA » sur l'image
    /// (décision du propriétaire, 2026-10-24) : la conversation dit déjà qu'AVE l'a créée.
    @ViewBuilder private var badges: some View {
        if media.simulated {
            Badge(text: UserMessages.simulatedBadge)
                .padding(8)
                .accessibilityHidden(true)
        }
    }

    private var actions: some View {
        HStack(spacing: 0) {
            if url != nil {
                iconButton("square.and.arrow.down", label: "Enregistrer dans Photos") { Task { await saveToPhotos() } }
            }
            if let url {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Partager")
            }
            if canRedo { iconButton("arrow.clockwise", label: "Refaire", action: onRedo) }
            iconButton("flag", label: "Signaler", action: onReport)
            Menu { moreMenu() } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Plus d'actions")
        }
        .font(.body)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .padding(.leading, -12)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    /// Ajout seul (« addOnly ») : l'app ne lit jamais la photothèque.
    private func saveToPhotos() async {
        guard let url else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            savedMessage = "Accès à Photos refusé. Vous pouvez l'autoriser dans les Réglages."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
            }
            savedMessage = "Image enregistrée dans Photos."
        } catch {
            savedMessage = "L'image n'a pas pu être enregistrée."
        }
    }
}

struct DocumentResultView: View {
    let media: MediaItem
    let url: URL?
    @State private var preview: URL?
    @State private var exporting = false
    @Environment(\.aveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                DocumentIcon(title: media.title).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(MediaFormat.detail(media)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if url != nil {
                    Button("Ouvrir") { preview = url }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(14)
            .background(theme.assistantBubble, in: .rect(cornerRadius: theme.cornerRadius))
            .accessibilityElement(children: .combine)
            if media.simulated { InfoLine(text: UserMessages.simulatedDocument) }
            if let url {
                HStack(spacing: 16) {
                    ShareLink(item: url) { Label("Partager", systemImage: "square.and.arrow.up") }
                    Button("Enregistrer dans Fichiers", systemImage: "folder") { exporting = true }
                }
                .font(.subheadline)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .quickLookPreview($preview)
        .sheet(isPresented: $exporting) {
            if let url { DocumentExporter(url: url).ignoresSafeArea() }
        }
    }
}

// MARK: Petits éléments

/// Aperçu réduit lu depuis le fichier gardé sur l'iPhone (une image 4K n'est jamais décodée en entier pour l'écran).
struct MediaThumbnail: View {
    let url: URL?
    let maxPixelSize: Int
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else {
                Rectangle().fill(.quaternary).aspectRatio(1, contentMode: .fit)
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = ImageProcessing.previewImage(at: url, maxPixelSize: maxPixelSize)
        }
    }
}

struct DocumentIcon: View {
    let title: String

    var body: some View {
        let ext = (title as NSString).pathExtension.uppercased()
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.tertiarySystemFill))
            .overlay {
                Text(ext.isEmpty ? "DOC" : String(ext.prefix(4)))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
    }
}

struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: .capsule)
    }
}

struct ErrorLine: View {
    let text: String
    @Environment(\.aveTheme) private var theme

    var body: some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(theme.warning)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

struct InfoLine: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

enum MediaFormat {
    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func detail(_ media: MediaItem) -> String {
        var parts: [String] = []
        if let w = media.width, let h = media.height { parts.append("\(w) × \(h)") }
        parts.append(size(media.byteCount))
        return parts.joined(separator: " · ")
    }

    static func aspect(_ size: ImageSize) -> String {
        switch size {
        case .square: return "Carré"
        case .portrait: return "Portrait"
        case .landscape: return "Paysage"
        }
    }
}

// MARK: Ponts UIKit (appareil photo, export vers Fichiers)

/// Appareil photo du système. Rien n'est gardé si la personne annule.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onFinish(image?.jpegData(compressionQuality: 0.9))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}

/// « Enregistrer dans Fichiers » : une COPIE ; le fichier reste dans la conversation.
struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}
#endif
