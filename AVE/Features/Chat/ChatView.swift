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
/// - « + » dans la barre : photo, appareil photo, fichier, créer une image (maquette validée le 2026-10-23) ;
/// - l'image se crée DANS la conversation (maquette validée le 2026-10-24) : une pastille « Image » dans la barre, le
///   format et la qualité dans la barre, la description en bulle ; plus de feuille séparée.
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
    /// « Renommer » dans le menu de titre. `nil` : pas d'historique, rien à renommer.
    let onRename: ((String) -> Void)?
    /// « Ouvrir les Réglages » sous une phrase non gardée (D13). `nil` : pas de bouton.
    let onOpenSettings: (() -> Void)?
    @State private var draft = ""
    /// D13 : la phrase gardée qu'on écrit (feuille « Ce que vous avez dit »).
    @State private var writingCollection: Int?
    /// « Renommer » du menu de titre : un champ dans une alerte du système.
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var correctionTarget: Int?
    @State private var sentCount = 0
    @State private var mediaSheet: MediaSheet?
    @State private var showPhotos = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var showCamera = false
    /// Idées rangées par défaut : une pastille « Idées » ; un toucher les déploie (maquette validée le 2026-10-23).
    @State private var ideasOpen = false
    @State private var dictation = DictationController()
    /// Mode image de la barre (`nil` : barre normale). Il reste après l'envoi, pour enchaîner une autre image.
    @State private var imageMode: ImageOptions?
    @State private var imagesSent = 0
    /// Hauteur visible du fil (sans les barres) et « ↓ » quand la fin est hors de vue.
    @State private var visibleHeight: CGFloat = 0
    @State private var showsJumpToEnd = false
    @FocusState private var composerFocused: Bool
    @Environment(\.aveTheme) private var theme

    public init(coordinator: SessionCoordinator, language: Binding<AVELanguageSelection>,
                captions: Binding<Bool> = .constant(true), title: String? = nil, firstName: String? = nil,
                haptics: Bool = true, onShowHistory: (() -> Void)? = nil, onNewConversation: (() -> Void)? = nil,
                onTranscriptChange: (([ChatMessage]) -> Void)? = nil, onRename: ((String) -> Void)? = nil,
                onOpenSettings: (() -> Void)? = nil) {
        self.coordinator = coordinator
        self._language = language
        self._captions = captions
        self.title = title
        self.firstName = firstName
        self.haptics = haptics
        self.onShowHistory = onShowHistory
        self.onNewConversation = onNewConversation
        self.onTranscriptChange = onTranscriptChange
        self.onRename = onRename
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        NavigationStack {
            messages
                .safeAreaBar(edge: .bottom) { composer }
                .navigationTitle(title ?? "AVE")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(LanguageTitleMenu(language: $language, options: coordinator.languageOptions,
                                            onRename: title != nil && onRename != nil ? {
                                                newTitle = title ?? ""
                                                renaming = true
                                            } : nil))
                .toolbar { toolbarContent }
        }
        .sheet(item: Binding(get: { writingCollection.map(WritingTarget.init) }, set: { writingCollection = $0?.id })) { target in
            SpokenTextSheet(languageName: coordinator.transcript.message(target.id)?.collection?.languageName ?? "") { text in
                Task { await coordinator.sendSpokenText(messageID: target.id, text: text) }
            }
        }
        .alert("Renommer la conversation", isPresented: $renaming) {
            TextField("Titre", text: $newTitle)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") {
                let cleaned = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { onRename?(cleaned) }
            }
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
        // Vibrations (maquette validée le 2026-10-24) : aux moments qui comptent, jamais pendant l'écriture.
        .sensoryFeedback(.impact(weight: .light), trigger: sentCount) { _, _ in haptics }
        .sensoryFeedback(.success, trigger: coordinator.tasksCompleted) { _, _ in haptics }
        .sensoryFeedback(.warning, trigger: coordinator.tasksFailed) { _, _ in haptics }
        .environment(\.aveHaptics, haptics)
        // `start()` est sans effet si la session tourne déjà. Pas d'arrêt dans `onDisappear` : iOS l'appelle aussi
        // quand le mode vocal plein écran recouvre cette vue, ce qui couperait la session. C'est le propriétaire du
        // coordinateur (l'app, ou l'app hôte) qui appelle `stop()` (déconnexion, nouvelle conversation).
        .task { await coordinator.start() }
    }

    // MARK: Barre du haut (Liquid Glass fournie par le système)

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if let onShowHistory {
            ToolbarItem(placement: .topBarLeading) {
                Button("Historique", systemImage: "line.3.horizontal", action: onShowHistory)
            }
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

    /// Défilement (maquette « Fluidité d'AVE », validée le 2026-10-24), comme ChatGPT et Claude : à l'envoi, la question
    /// monte en haut de l'écran et le dernier échange occupe au moins la hauteur visible, pour que la réponse s'écrive
    /// dessous sans que le fil saute. Rien ne ramène de force en bas pendant l'écriture ; « ↓ » revient à la fin.
    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    statusLine
                    let list = coordinator.transcript.messages
                    let captions = imageCaptions
                    let split = coordinator.transcript.lastTurnStart
                    ForEach(list[..<split]) { message in
                        row(message, captions: captions)
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(list[split...]) { message in
                            row(message, captions: captions)
                        }
                        ForEach(coordinator.pendingTexts) { pending in
                            PendingBubble(text: pending.text)
                        }
                        if showsThinking {
                            ThinkingRow().transition(.opacity)
                        }
                    }
                    .frame(minHeight: split < list.count ? max(0, visibleHeight - 24) : nil, alignment: .top)
                    Color.clear.frame(height: 1).id(Self.endID)
                }
                .animation(.easeInOut(duration: 0.2), value: showsThinking)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .overlay { if isEmpty { emptyState } }
            .overlay(alignment: .bottom) {
                if showsJumpToEnd {
                    Button("Aller à la fin", systemImage: "arrow.down") {
                        withAnimation(.smooth) { proxy.scrollTo(Self.endID, anchor: .bottom) }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .padding(.bottom, 8)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: showsJumpToEnd)
            .scrollDismissesKeyboard(.interactively)
            // Ouverture d'une conversation : la fin. Ensuite, aucun ancrage automatique en bas (la réponse ne tire pas
            // le fil pendant qu'on lit).
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(geometry)
            } action: { _, metrics in
                visibleHeight = metrics.visibleHeight
                showsJumpToEnd = metrics.distanceToEnd > 120
            }
            .background((theme.background ?? Color(.systemBackground)).ignoresSafeArea())
            .onChange(of: coordinator.transcript.messages.last?.id) { _, newID in
                guard let newID, coordinator.transcript.messages.last?.role == .user else { return }
                withAnimation(.smooth(duration: 0.45)) { proxy.scrollTo(newID, anchor: .top) }
            }
            .onChange(of: coordinator.pendingTexts.count) { old, new in
                if new > old { withAnimation(.smooth) { proxy.scrollTo(Self.endID, anchor: .bottom) } }
            }
            // Autre conversation (nouvelle, ou rouverte depuis l'historique) : on repart de sa fin.
            .onChange(of: ObjectIdentifier(coordinator)) { _, _ in proxy.scrollTo(Self.endID, anchor: .bottom) }
        }
    }

    private static let endID = "fin-du-fil"

    @ViewBuilder private func row(_ message: ChatMessage, captions: [Int: String]) -> some View {
        if let collection = message.collection {
            SpokenCollectionRow(collection: collection, onWrite: { writingCollection = message.id },
                                onOpenSettings: onOpenSettings)
            .id(message.id)
        } else if message.media != nil || message.task != nil {
            MediaMessageView(message: message, coordinator: coordinator,
                             showsActions: message.id == coordinator.transcript.messages.last?.id,
                             onSheet: { mediaSheet = $0 })
            .id(message.id)
        } else if let caption = captions[message.id] {
            // La description d'une image, puis « Image · Paysage · 1080p » (maquette, écran 3).
            VStack(alignment: .trailing, spacing: 6) {
                bubble(for: message)
                Label(caption, systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 6)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .id(message.id)
        } else {
            bubble(for: message).id(message.id)
        }
    }

    /// Une description d'image est la bulle de la personne suivie de la carte (ou de l'image) d'une création.
    private var imageCaptions: [Int: String] {
        let list = coordinator.transcript.messages
        var captions: [Int: String] = [:]
        for (message, next) in zip(list, list.dropFirst()) where message.role == .user && message.media == nil {
            if let request = next.task?.request ?? next.media?.request,
               let caption = MediaTaskText.imageCaption(for: request) {
                captions[message.id] = caption
            }
        }
        return captions
    }

    private func bubble(for message: ChatMessage) -> some View {
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
                        ForEach(Idea.all.filter { idea in
                            if idea.createsImage { return coordinator.offers(.generate) }
                            return coordinator.supportsMedia || !idea.needsMedia
                        }) { idea in
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
            enterImageMode()
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

    /// « Créer comme image » au-dessus de la barre : la phrase commence comme une demande d'image (jamais en mode image).
    private var suggestsImageMode: Bool {
        // D12 : un moteur qui comprend la phrase seul n'a pas besoin de la proposition.
        imageMode == nil && coordinator.offers(.generate) && !(coordinator.engine?.createsImagesFromChat ?? false)
            && ImageIntent.suggestsImage(draft)
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if isEmpty && draft.isEmpty && imageMode == nil { ideasBar }
            if suggestsImageMode {
                Button { enterImageMode() } label: {
                    Label("Créer comme image", systemImage: "photo").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityHint("Passe en mode image ; rien n'est créé avant l'envoi.")
            }
            // Saisie en deux étages (validée) : le texte, puis « + » à gauche et le bouton rond à droite.
            VStack(alignment: .leading, spacing: 2) {
                if imageMode != nil {
                    imageModeChip
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                }
                // Pièces jointes en cours d'envoi, dans la barre (maquette 2).
                ForEach(coordinator.attachmentDrafts) { draft in
                    AttachmentDraftRow(draft: draft, url: draft.localName.flatMap { coordinator.mediaURL(named: $0) },
                                       onRemove: { coordinator.cancelAttachment(draft.id) })
                        .padding(.top, 6)
                }
                if coordinator.supportsTextInput {
                    TextField(composerPrompt, text: $draft, axis: .vertical)
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
                    if imageMode != nil { imageOptions }
                    Spacer(minLength: 0)
                    if coordinator.supportsTextInput { dictationButton }
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
        .animation(.snappy, value: suggestsImageMode)
        .animation(.snappy, value: imageMode != nil)
        .onChange(of: draft) { _, new in if !new.isEmpty, ideasOpen { withAnimation(.snappy) { ideasOpen = false } } }
    }

    // MARK: Mode image (maquette « Créer une image dans AVE », validée le 2026-10-24)

    private var composerPrompt: String {
        guard imageMode != nil else { return "Demandez à AVE" }
        return imagesSent == 0 ? "Décrivez l'image" : "Décrivez une autre image"
    }

    /// La pastille « Image » : un toucher quitte le mode image (la croix le dit).
    private var imageModeChip: some View {
        Button { exitImageMode() } label: {
            HStack(spacing: 6) {
                Image(systemName: "photo")
                Text("Image")
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(theme.accent)
        .accessibilityLabel("Mode image")
        .accessibilityHint("Touchez pour revenir aux questions.")
    }

    /// Format et qualité, menus du système dans la barre (défaut du moteur : carré, 1080p).
    private var imageOptions: some View {
        HStack(spacing: 0) {
            Picker("Format", selection: Binding(get: { imageMode?.size ?? .square }, set: { imageMode?.size = $0 })) {
                ForEach(ImageSize.allCases, id: \.self) { Text(MediaFormat.aspect($0)).tag($0) }
            }
            Picker("Qualité", selection: Binding(get: { imageMode?.quality ?? .hd }, set: { imageMode?.quality = $0 })) {
                Text("1080p").tag(ImageQuality.hd)
                Text("4K").tag(ImageQuality.uhd)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.subheadline.weight(.semibold))
        .tint(.primary)
        .frame(minHeight: 44)
    }

    private func enterImageMode() {
        withAnimation(.snappy) {
            ideasOpen = false
            if imageMode == nil { imageMode = ImageOptions() }
        }
        composerFocused = true
    }

    private func exitImageMode() {
        withAnimation(.snappy) { imageMode = nil }
        imagesSent = 0
    }

    /// Micro de dictée : la reconnaissance d'Apple, sur l'iPhone ; le texte s'écrit dans la barre, rien ne part seul.
    private var dictationButton: some View {
        Button {
            if dictation.isListening {
                dictation.finish()
            } else {
                Task {
                    if let message = await dictation.start(current: draft, update: { draft = $0 }) {
                        coordinator.notice = message
                    }
                }
            }
        } label: {
            Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                .font(.body.weight(.semibold))
                .foregroundStyle(dictation.isListening ? theme.accent : Color.primary)
                .symbolEffect(.pulse, isActive: dictation.isListening)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dictation.isListening ? "Terminer la dictée" : "Dicter")
        .accessibilityHint(dictation.isListening ? "" : "Écrit ce que vous dites dans la barre, sans l'envoyer.")
    }

    /// AVE parle dans la conversation écrite (lecture à voix haute ou réponse dite).
    private var readingAloud: Bool {
        coordinator.mode == .text && (coordinator.replayingMessageID != nil || coordinator.phase == .speaking)
    }

    /// Un seul bouton rond, dans la barre : « envoyer » (bleu AVE) dès qu'on écrit, « arrêter » pendant une réponse,
    /// sinon « mode vocal ». Bouton Liquid Glass du système (exigence du propriétaire : aucun bouton dessiné à la main) ;
    /// envoyer est le seul aplat de couleur de l'écran.
    private var actionButton: some View {
        let stops = !canSend && coordinator.isResponding
        return Button {
            if canSend { send() } else if stops { Task { await coordinator.stopResponse() } } else { openVoiceMode() }
        } label: {
            Image(systemName: canSend ? "arrow.up" : stops ? "stop.fill" : "waveform")
                .font(.body.weight(.semibold))
                .foregroundStyle(canSend ? theme.onAccent : Color(.systemBackground))
                .frame(width: 22, height: 22)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(canSend ? theme.accent : Color.primary)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(canSend ? "Envoyer" : stops ? "Arrêter la réponse" : "Mode vocal")
        .accessibilityHint(canSend || stops ? "" : "Parler avec l'assistant.")
    }

    private func send() {
        dictation.cancel()
        let message = draft
        if let options = imageMode {
            let prompt = message.trimmingCharacters(in: .whitespacesAndNewlines)
            // Trop longue : la description reste dans la barre pour être raccourcie.
            guard prompt.count <= MediaTaskRequest.promptMaxCharacters else {
                coordinator.notice = UserMessages.mediaError(code: "prompt_too_long")
                return
            }
            draft = ""
            sentCount += 1
            imagesSent += 1
            Task { await coordinator.createImage(prompt: prompt, size: options.size, quality: options.quality) }
            return
        }
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
            if coordinator.offers(.generate) {
                Button("Créer une image", systemImage: "sparkles") { enterImageMode() }
            }
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
        dictation.cancel()
        composerFocused = false
        Task { await coordinator.setMode(.voice) }
    }

    /// Le mode vocal est affiché tant que la session est en mode voix (le micro refusé la repasse en texte : la vue se ferme).
    private var voiceModeBinding: Binding<Bool> {
        Binding(get: { coordinator.mode == .voice },
                set: { if !$0 { Task { await coordinator.setMode(.text) } } })
    }
}

/// Mesures du défilement, en points.
struct ScrollMetrics: Equatable {
    var visibleHeight: CGFloat
    var distanceToEnd: CGFloat

    init(_ geometry: ScrollGeometry) {
        visibleHeight = geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
        let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height - geometry.contentInsets.bottom
        distanceToEnd = geometry.contentSize.height - visibleBottom
    }
}

/// Format et qualité choisis dans la barre en mode image.
struct ImageOptions: Equatable {
    var size: ImageSize = .square
    var quality: ImageQuality = .hd
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

    /// D11 : l'idée « Créer une image » suit `image_tasks`.
    var createsImage: Bool {
        if case .createImage = action { return true }
        return false
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

/// Avis à lire en tête de conversation : boîte de groupe du système (maquette « AVE tout natif », validée le
/// 2026-10-24), icône, texte et fermeture.
struct NoticeBanner: View {
    let text: String
    let systemImage: String
    let onDismiss: (() -> Void)?
    @Environment(\.aveTheme) private var theme

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(theme.warning)
                    .accessibilityHidden(true)
                Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                if let onDismiss {
                    Button("Fermer", systemImage: "xmark", action: onDismiss)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .tint(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.vertical, -12)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
