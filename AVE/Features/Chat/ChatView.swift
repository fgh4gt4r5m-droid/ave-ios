#if os(iOS)
import AVECore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Écran principal, aux standards des assistants d'iOS (ChatGPT, Claude, Gemini ; proposition 2 validée le 2026-10-23) :
/// - barre du haut système : historique à gauche, titre (conversation ou « AVE ») + langue au centre, nouvelle
///   conversation à droite ;
/// - accueil : salutation et quatre suggestions qui remplissent la barre d'un toucher ;
/// - réponses mises en forme, actions (copier, lire, partager, réessayer, avis), appui long = menu natif ;
/// - messages écrits hors connexion affichés « en attente », envoyés au retour du réseau ;
/// - UNE barre de saisie Liquid Glass ; le mode vocal s'ouvre en plein écran sur la MÊME session ;
/// - « + » dans la barre : photo, appareil photo, fichier, créer une image (maquette validée le 2026-10-23).
public struct ChatView: View {
    let coordinator: SessionCoordinator
    @Binding var language: AVELanguageSelection
    /// Sous-titres du mode vocal (réglage partagé avec l'écran des réglages).
    @Binding var captions: Bool
    /// Titre de la conversation (historique) ; `nil` : « AVE ».
    let title: String?
    /// Prénom pour la salutation (facultatif, gardé sur l'iPhone).
    let firstName: String?
    let haptics: Bool
    /// Ouvre l'historique. `nil` (app hôte) : pas de bouton.
    let onShowHistory: (() -> Void)?
    /// Repart d'une conversation vide (nouvelle session côté moteur). `nil` : pas de bouton.
    let onNewConversation: (() -> Void)?
    /// Appelé quand le fil change : l'app hôte l'enregistre dans l'historique.
    let onTranscriptChange: (([ChatMessage]) -> Void)?
    @State private var draft = ""
    @State private var showLanguages = false
    @State private var correctionTarget: Int?
    @State private var sentCount = 0
    @State private var mediaSheet: MediaSheet?
    @State private var showPhotos = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var showCamera = false
    @FocusState private var composerFocused: Bool
    @Environment(\.aveTheme) private var theme

    public init(coordinator: SessionCoordinator, language: Binding<AVELanguageSelection>,
                captions: Binding<Bool> = .constant(true), title: String? = nil, firstName: String? = nil,
                haptics: Bool = true, onShowHistory: (() -> Void)? = nil, onNewConversation: (() -> Void)? = nil,
                onTranscriptChange: (([ChatMessage]) -> Void)? = nil) {
        self.coordinator = coordinator
        self._language = language
        self._captions = captions
        self.title = title
        self.firstName = firstName
        self.haptics = haptics
        self.onShowHistory = onShowHistory
        self.onNewConversation = onNewConversation
        self.onTranscriptChange = onTranscriptChange
    }

    public var body: some View {
        NavigationStack {
            messages
                .safeAreaBar(edge: .bottom) { composer }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showLanguages) {
            LanguagePicker(selection: $language, options: coordinator.languageOptions)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: Binding(get: { coordinator.learningPrompt != nil },
                                    set: { if !$0 { coordinator.dismissLearningPrompt() } })) {
            if let prompt = coordinator.learningPrompt {
                LearningPromptView(prompt: prompt) { granted in Task { await coordinator.answerLearning(granted: granted) } }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: Binding(get: { correctionTarget != nil }, set: { if !$0 { correctionTarget = nil } })) {
            FeedbackCorrectionView { correction in
                if let id = correctionTarget { Task { await coordinator.sendFeedback(messageID: id, rating: .down, correction: correction) } }
                correctionTarget = nil
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $mediaSheet) { sheet in mediaSheetView(sheet) }
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                // Le sélecteur de photos ne donne pas le nom du fichier sans accès à la photothèque : « Photo ».
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await coordinator.attachImage(data, fileName: "Photo")
                }
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: Self.importableTypes) { result in
            if case .success(let url) = result { importFile(at: url) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                showCamera = false
                if let data { Task { await coordinator.attachImage(data, fileName: "Photo.jpg") } }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: voiceModeBinding) {
            VoiceModeView(coordinator: coordinator, language: $language, captions: $captions, haptics: haptics)
        }
        .onChange(of: language) { _, new in
            Task { await coordinator.setLanguage(new.language) }
        }
        .onChange(of: coordinator.transcript.messages) { _, messages in
            onTranscriptChange?(messages)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: sentCount) { _, _ in haptics }
        // `start()` est sans effet si la session tourne déjà. Pas d'arrêt dans `onDisappear` : iOS l'appelle aussi
        // quand le mode vocal plein écran recouvre cette vue, ce qui couperait la session. C'est le propriétaire du
        // coordinateur (l'app, ou l'app hôte) qui appelle `stop()` (déconnexion, nouvelle conversation).
        .task { await coordinator.start() }
    }

    // MARK: Barre du haut (Liquid Glass fournie par le système)

    private var languageName: String {
        LanguageCatalog.option(for: language.language)?.name ?? "Langue"
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if let onShowHistory {
            ToolbarItem(placement: .topBarLeading) {
                Button("Historique", systemImage: "line.3.horizontal", action: onShowHistory)
            }
        }
        ToolbarItem(placement: .principal) {
            // Comme le choix du modèle dans ChatGPT : le titre, et dessous ce qu'on peut changer (la langue).
            Button { showLanguages = true } label: {
                VStack(spacing: 0) {
                    Text(title ?? "AVE").font(.headline).lineLimit(1)
                    HStack(spacing: 3) {
                        Text(languageName)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 220, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title ?? "AVE"), langue : \(languageName)")
            .accessibilityHint("Choisir la langue de la conversation.")
        }
        if let onNewConversation {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Nouvelle conversation", systemImage: "square.and.pencil", action: onNewConversation)
                    .disabled(coordinator.transcript.messages.isEmpty && coordinator.pendingTexts.isEmpty)
            }
        }
    }

    // MARK: Conversation

    private var isEmpty: Bool {
        coordinator.transcript.messages.isEmpty && coordinator.pendingTexts.isEmpty && coordinator.attachmentDrafts.isEmpty
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    statusLine
                    ForEach(coordinator.transcript.messages) { message in
                        if message.media != nil || message.task != nil {
                            MediaMessageView(message: message, coordinator: coordinator,
                                             showsActions: message.id == coordinator.transcript.messages.last?.id,
                                             onSheet: { mediaSheet = $0 })
                            .id(message.id)
                        } else {
                            MessageBubble(
                                message: message,
                                canReadAloud: coordinator.canReadAloud(messageID: message.id),
                                isReplaying: coordinator.replayingMessageID == message.id,
                                canFeedback: coordinator.canGiveFeedback,
                                feedbackSent: coordinator.feedbackGiven.contains(message.id),
                                onFeedback: { rating in
                                    if rating == .up { Task { await coordinator.sendFeedback(messageID: message.id, rating: .up) } }
                                    else { correctionTarget = message.id }
                                },
                                onReplay: { Task { await coordinator.readAloud(messageID: message.id) } },
                                onConfirm: { coordinator.confirmAction(messageID: message.id) },
                                onDecline: { coordinator.declineAction(messageID: message.id) },
                                onRetry: retryAction(for: message),
                                onEdit: editAction(for: message))
                            .id(message.id)
                        }
                    }
                    ForEach(coordinator.pendingTexts) { pending in
                        PendingBubble(text: pending.text)
                    }
                    if showsThinking {
                        ThinkingRow().transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showsThinking)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .overlay(alignment: .bottom) { if isEmpty { emptyState } }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .background((theme.background ?? Color(.systemBackground)).ignoresSafeArea())
            .onChange(of: coordinator.transcript.messages.count) { _, _ in
                if let last = coordinator.transcript.messages.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    /// « Réflexion… » sous la question, tant que la réponse n'a pas commencé à s'écrire (ensuite, la réponse qui
    /// arrive suffit).
    private var showsThinking: Bool {
        guard coordinator.orbState == .thinking else { return false }
        if let last = coordinator.transcript.messages.last, last.role == .assistant, last.status == .streaming { return false }
        return true
    }

    /// Accueil : le logo au repos (l'Afrique dessinée par les barres), la salutation et quatre suggestions juste
    /// au-dessus de la barre (comme ChatGPT et Gemini).
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            AVELiveMark(phase: .idle).frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 2) {
                Text(firstName.map { "Bonjour \($0)." } ?? "Bonjour.")
                Text("Que faisons-nous ?").foregroundStyle(.secondary)
            }
            .font(.title.weight(.bold))
            .accessibilityElement(children: .combine)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Suggestion.all) { suggestion in
                    Button { use(suggestion) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Image(systemName: suggestion.symbol)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(theme.accent)
                                .padding(.bottom, 2)
                            Text(suggestion.title).font(.headline)
                            Text(suggestion.detail).font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                        .padding(14)
                        .background(theme.assistantBubble, in: .rect(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(suggestion.prefix == nil ? "Ouvre le mode vocal." : "Remplit la barre de saisie.")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func use(_ suggestion: Suggestion) {
        if let prefix = suggestion.prefix {
            draft = prefix
            composerFocused = true
        } else {
            openVoiceMode()
        }
    }

    private func edit(_ text: String) {
        draft = text
        composerFocused = true
    }

    /// « Réessayer » : seulement sous une réponse terminée de l'assistant (pas sous une carte d'action).
    private func retryAction(for message: ChatMessage) -> (() -> Void)? {
        guard message.role == .assistant, message.card == nil, message.status != .streaming else { return nil }
        return { Task { await coordinator.retry(messageID: message.id) } }
    }

    /// « Modifier » : seulement sur une question de la personne ; elle revient dans la barre pour être corrigée.
    private func editAction(for message: ChatMessage) -> (() -> Void)? {
        guard message.role == .user else { return nil }
        let text = message.text
        return { edit(text) }
    }

    /// Une ligne discrète en tête : erreur à lire (fermable), sinon état de la connexion. Rien quand tout va bien.
    @ViewBuilder private var statusLine: some View {
        if let text = coordinator.notice ?? coordinator.learningMessage {
            NoticeBanner(text: text, systemImage: "exclamationmark.triangle.fill", onDismiss: {
                if coordinator.notice != nil { coordinator.dismissNotice() } else { coordinator.dismissLearningMessage() }
            })
        } else if !coordinator.pendingTexts.isEmpty {
            Label(UserMessages.offlineQueued, systemImage: "wifi.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        } else if let text = UserMessages.connection(coordinator.connection) {
            Label(text, systemImage: "wifi.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: Barre de saisie

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var composer: some View {
        VStack(spacing: 6) {
            VStack(spacing: 0) {
                // Pièces jointes en cours d'envoi, dans la barre (maquette 2).
                ForEach(coordinator.attachmentDrafts) { draft in
                    AttachmentDraftRow(draft: draft, url: draft.localName.flatMap { coordinator.mediaURL(named: $0) },
                                       onRemove: { coordinator.cancelAttachment(draft.id) })
                        .padding(.top, 6)
                }
                HStack(alignment: .bottom, spacing: 4) {
                    if coordinator.supportsMedia {
                        attachMenu
                            .padding(.leading, 4)
                            .padding(.bottom, 2)
                    }
                    if coordinator.supportsTextInput {
                        TextField("Message", text: $draft, axis: .vertical)
                            .lineLimit(1...6)
                            .focused($composerFocused)
                            .padding(.leading, coordinator.supportsMedia ? 0 : 18)
                            .padding(.vertical, 14)
                    } else {
                        Text(UserMessages.textInputUnavailable)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 18)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    actionButton
                        .padding(.trailing, 4)
                        .padding(.bottom, 2)
                }
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
            if let demo = coordinator.demoNotice {
                Text(demo)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.15), value: canSend)
    }

    /// Un seul bouton rond, dans la barre : « mode vocal » quand le champ est vide, « envoyer » dès qu'on écrit.
    private var actionButton: some View {
        Button {
            if canSend { send() } else { openVoiceMode() }
        } label: {
            Image(systemName: canSend ? "arrow.up" : "waveform")
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.onAccent)
                .frame(width: 38, height: 38)
                .background(theme.accent, in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(canSend ? "Envoyer" : "Mode vocal")
        .accessibilityHint(canSend ? "" : "Parler avec l'assistant.")
    }

    private func send() {
        let message = draft
        draft = ""
        sentCount += 1
        Task { await coordinator.sendText(message) }
    }

    // MARK: Fichiers et images

    /// Le « + » : un menu système juste au-dessus de la barre (maquette 1).
    private var attachMenu: some View {
        Menu {
            Button { showPhotos = true } label: {
                Label { Text("Photos"); Text("Depuis la photothèque") } icon: { Image(systemName: "photo.on.rectangle") }
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Appareil photo", systemImage: "camera") { showCamera = true }
            }
            Button { showFiles = true } label: {
                Label { Text("Fichier"); Text("PDF, Word, texte · 10 Mo max") } icon: { Image(systemName: "doc") }
            }
            Button("Créer une image", systemImage: "sparkles") { mediaSheet = .createImage }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .accessibilityLabel("Joindre ou créer")
    }

    static let importableTypes: [UTType] =
        [.pdf, .plainText, .image] + [UTType(filenameExtension: "docx")].compactMap { $0 }

    /// Fichier choisi dans Fichiers : une image passe par la préparation des photos, le reste part tel quel.
    private func importFile(at url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
        let kind: MediaItem.Kind = isImage ? .image : .document
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        // Ne pas charger en mémoire un fichier refusé de toute façon (une photo peut être réduite : marge ×5).
        let limit = isImage ? MediaLimits.maxUploadBytes * 5 : MediaLimits.maxUploadBytes
        guard size <= limit else {
            coordinator.rejectAttachment(fileName: name, byteCount: size, kind: kind, code: "file_too_large")
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            coordinator.rejectAttachment(fileName: name, byteCount: size, kind: kind, code: "file_missing")
            return
        }
        if isImage {
            Task { await coordinator.attachImage(data, fileName: name) }
        } else {
            coordinator.attachDocument(data, fileName: name)
        }
    }

    @ViewBuilder private func mediaSheetView(_ sheet: MediaSheet) -> some View {
        switch sheet {
        case .createImage:
            CreateImageSheet { prompt, size, quality in
                Task { await coordinator.createImage(prompt: prompt, size: size, quality: quality) }
            }
            .presentationDetents([.medium, .large])
        case .edit(let id):
            EditImageSheet(needsRights: needsRights(id)) { instruction, rights in
                Task { await coordinator.editImage(messageID: id, instruction: instruction, rightsConfirmed: rights) }
            }
            .presentationDetents([.medium, .large])
        case .rights(let id, let action):
            RightsSheet(actionTitle: Self.title(of: action)) {
                Task {
                    switch action {
                    case .upscale(let target):
                        await coordinator.upscaleImage(messageID: id, target: target, rightsConfirmed: true)
                    case .extend(let aspect):
                        await coordinator.extendImage(messageID: id, aspect: aspect, rightsConfirmed: true)
                    }
                }
            }
            .presentationDetents([.medium])
        case .rewrite(let id):
            RewriteSheet { instruction in
                Task { await coordinator.transformDocument(messageID: id, action: .rewrite, instruction: instruction) }
            }
            .presentationDetents([.medium])
        case .report(let id):
            ReportSheet { reason, note in
                Task { await coordinator.report(messageID: id, reason: reason, note: note) }
            }
            .presentationDetents([.large])
        }
    }

    private func needsRights(_ messageID: Int) -> Bool {
        guard let media = coordinator.transcript.message(messageID)?.media else { return false }
        return media.requiresRightsForTask() && !media.rightsConfirmed
    }

    private static func title(of action: MediaSheet.RightsAction) -> String {
        switch action {
        case .upscale(let target): return target == .uhd ? "Agrandir en 4K" : "Agrandir en 1080p"
        case .extend(let aspect): return "Prolonger en \(MediaFormat.aspect(aspect).lowercased())"
        }
    }


    // MARK: Mode vocal

    private func openVoiceMode() {
        composerFocused = false
        Task { await coordinator.setMode(.voice) }
    }

    /// Le mode vocal est affiché tant que la session est en mode voix (le micro refusé la repasse en texte : la vue se ferme).
    private var voiceModeBinding: Binding<Bool> {
        Binding(get: { coordinator.mode == .voice },
                set: { if !$0 { Task { await coordinator.setMode(.text) } } })
    }
}

/// Suggestions de l'accueil. `prefix` remplit la barre ; `nil` ouvre le mode vocal. Formulées sans rien promettre
/// que le moteur ne fasse pas : ce sont des débuts de phrase, l'utilisateur complète.
struct Suggestion: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    let prefix: String?

    static let all: [Suggestion] = [
        Suggestion(id: "traduire", symbol: "character.bubble", title: "Traduire", detail: "une phrase en français",
                   prefix: "Traduis en français : "),
        Suggestion(id: "ecrire", symbol: "square.and.pencil", title: "Écrire", detail: "un message pour un proche",
                   prefix: "Écris un message pour "),
        Suggestion(id: "expliquer", symbol: "questionmark.circle", title: "Expliquer", detail: "un mot ou une idée",
                   prefix: "Explique-moi simplement : "),
        Suggestion(id: "parler", symbol: "waveform", title: "Parler", detail: "à voix haute avec AVE", prefix: nil),
    ]
}

/// L'assistant prépare sa réponse : le logo en réflexion (l'Afrique devient une onde, puis un cercle) et le mot qui le dit.
struct ThinkingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            AVELiveMark(phase: .thinking).frame(width: 36, height: 36)
            Text("Réflexion…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(OrbState.thinking.label)
    }
}

/// Message écrit hors connexion : même bulle que les autres, avec la mention « en attente du réseau ».
struct PendingBubble: View {
    let text: String
    @Environment(\.aveTheme) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(text)
                .foregroundStyle(theme.userBubbleText)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(theme.userBubble, in: .rect(cornerRadius: theme.cornerRadius))
                .opacity(0.7)
            Label(UserMessages.waitingForNetwork, systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
        .accessibilityElement(children: .combine)
    }
}

/// Avis à lire en tête de conversation : icône + texte + fermeture.
struct NoticeBanner: View {
    let text: String
    let systemImage: String
    let onDismiss: (() -> Void)?
    @Environment(\.aveTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button("Fermer", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .padding(.vertical, -12)
            }
        }
        .padding(14)
        .background(theme.assistantBubble, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
#endif
