#if os(iOS)
import AVECore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Écran principal, aux standards des assistants d'iOS (ChatGPT, Claude, Gemini ; proposition 2 validée le 2026-10-23) :
/// - barre du haut système : historique à gauche, titre (conversation ou « AVE ») + langue au centre, nouvelle
///   conversation à droite ;
/// - accueil : salutation et six exemples de questions du quotidien qui remplissent la barre d'un toucher (maquette
///   validée le 2026-10-23) ;
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
    /// Idées rangées par défaut : une pastille « Idées » ; un toucher les déploie (maquette validée le 2026-10-23).
    @State private var ideasOpen = false
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
                                onEdit: editAction(for: message),
                                showsMark: message.id == latestAnswerID)
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
            .overlay { if isEmpty { emptyState } }
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

    /// Dernière réponse écrite de l'assistant : elle seule porte le symbole en tête.
    private var latestAnswerID: Int? {
        coordinator.transcript.messages.last { $0.role == .assistant && $0.card == nil && $0.media == nil && $0.task == nil }?.id
    }

    /// « Réflexion… » sous la question, tant que la réponse n'a pas commencé à s'écrire (ensuite, la réponse qui
    /// arrive suffit).
    private var showsThinking: Bool {
        guard coordinator.orbState == .thinking else { return false }
        if let last = coordinator.transcript.messages.last, last.role == .assistant, last.status == .streaming { return false }
        return true
    }

    /// Accueil épuré (validé le 2026-10-23) : presque vide. Le symbole au repos, « Bonjour, Fatou », « Comment puis-je vous
    /// aider ? ». Les idées sont rangées au-dessus de la saisie, sous le pouce.
    private var emptyState: some View {
        VStack(spacing: 14) {
            AVELiveMark(phase: .idle).frame(width: 64, height: 64)
            Text(firstName.map { "Bonjour, \($0)" } ?? "Bonjour")
                .font(.title.weight(.semibold))
            Text("Comment puis-je vous aider ?")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }

    /// Une pastille « Idées » ; touchée, une rangée compacte de boutons en verre défile sur le côté ; la croix la range.
    /// Les idées se rangent seules dès qu'on écrit ou qu'on en choisit une.
    private var ideasBar: some View {
        HStack(spacing: 8) {
            if ideasOpen {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Idea.all.filter { coordinator.supportsMedia || !$0.needsMedia }) { idea in
                            Button { use(idea) } label: {
                                Label(idea.title, systemImage: idea.symbol).font(.subheadline)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .transition(.move(edge: .leading).combined(with: .opacity))
                Button("Ranger les idées", systemImage: "xmark") { withAnimation(.snappy) { ideasOpen = false } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            } else {
                Button { withAnimation(.snappy) { ideasOpen = true } } label: {
                    Label("Idées", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .accessibilityHint("Affiche des idées de questions.")
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: 44)
    }

    private func use(_ idea: Idea) {
        withAnimation(.snappy) { ideasOpen = false }
        switch idea.action {
        case .prefix(let text):
            draft = text
            composerFocused = true
        case .createImage:
            mediaSheet = .createImage
        case .attachDocument:
            showFiles = true
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
            if isEmpty && draft.isEmpty { ideasBar }
            // Saisie en deux étages (validée) : le texte, puis « + » à gauche et le bouton rond à droite.
            VStack(alignment: .leading, spacing: 2) {
                // Pièces jointes en cours d'envoi, dans la barre (maquette 2).
                ForEach(coordinator.attachmentDrafts) { draft in
                    AttachmentDraftRow(draft: draft, url: draft.localName.flatMap { coordinator.mediaURL(named: $0) },
                                       onRemove: { coordinator.cancelAttachment(draft.id) })
                        .padding(.top, 6)
                }
                if coordinator.supportsTextInput {
                    TextField("Demandez à AVE", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($composerFocused)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                } else {
                    Text(UserMessages.textInputUnavailable)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 4) {
                    if coordinator.supportsMedia { attachMenu }
                    Spacer(minLength: 0)
                    actionButton
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
            // Écrans validés : un halo très léger autour de la saisie quand AVE lit une réponse à voix haute.
            .background { ReadingHalo(active: readingAloud, level: coordinator.playbackLevel) }
            .animation(.easeInOut(duration: 0.4), value: readingAloud)
            // Deux petites lignes au plus : la mention d'essai (selon l'état du moteur), puis l'avertissement.
            VStack(spacing: 2) {
                if let demo = coordinator.demoNotice { Text(demo) }
                Text("AVE peut se tromper. Vérifiez les informations importantes.")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.15), value: canSend)
        .onChange(of: draft) { _, new in if !new.isEmpty, ideasOpen { withAnimation(.snappy) { ideasOpen = false } } }
    }

    /// AVE parle dans la conversation écrite (lecture à voix haute ou réponse dite).
    private var readingAloud: Bool {
        coordinator.mode == .text && (coordinator.replayingMessageID != nil || coordinator.phase == .speaking)
    }

    /// Un seul bouton rond, dans la barre : « envoyer » (bleu AVE) dès qu'on écrit, « arrêter » pendant une réponse,
    /// sinon « mode vocal ». Envoyer est le seul aplat de couleur de l'écran.
    private var actionButton: some View {
        let stops = !canSend && coordinator.isResponding
        return Button {
            if canSend { send() } else if stops { Task { await coordinator.stopResponse() } } else { openVoiceMode() }
        } label: {
            Image(systemName: canSend ? "arrow.up" : stops ? "stop.fill" : "waveform")
                .font(.body.weight(.semibold))
                .foregroundStyle(canSend ? theme.onAccent : Color(.systemBackground))
                .frame(width: 36, height: 36)
                .background(canSend ? theme.accent : Color.primary, in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(canSend ? "Envoyer" : stops ? "Arrêter la réponse" : "Mode vocal")
        .accessibilityHint(canSend || stops ? "" : "Parler avec l'assistant.")
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

/// Idées de questions du quotidien (validées le 2026-10-23), rangées par défaut. `needsMedia` : seulement si le moteur
/// accepte les fichiers. Formulées sans rien promettre que le moteur ne fasse pas : des débuts de phrase à compléter.
struct Idea: Identifiable {
    enum Action {
        case prefix(String)
        case createImage
        case attachDocument
    }

    let id: String
    let symbol: String
    let title: String
    let action: Action

    var needsMedia: Bool {
        if case .prefix = action { return false }
        return true
    }

    static let all: [Idea] = [
        Idea(id: "lettre", symbol: "envelope", title: "Écrire une lettre", action: .prefix("Écris une lettre à la mairie pour ")),
        Idea(id: "facture", symbol: "doc.text", title: "Comprendre une facture",
             action: .prefix("Explique-moi simplement cette facture : ")),
        Idea(id: "budget", symbol: "creditcard", title: "Budget du mois",
             action: .prefix("Aide-moi à faire un budget pour le mois : ")),
        Idea(id: "image", symbol: "photo", title: "Créer une image", action: .createImage),
        Idea(id: "resume", symbol: "doc.plaintext", title: "Résumer un document", action: .attachDocument),
        Idea(id: "chercher", symbol: "magnifyingglass", title: "Chercher une info", action: .prefix("Cherche ")),
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
