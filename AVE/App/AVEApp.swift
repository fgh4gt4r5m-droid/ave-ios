import AVECore
import AVEKit
import SwiftUI

@main
struct AVEApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Assemble configuration, connexion, audio réel, coordinateur de session, historique local et réglages.
struct RootView: View {
    @State private var environment: AppEnvironment?
    @State private var session: AuthSession?
    @State private var signIn: SignInViewModel?
    @State private var authState: AuthSession.State = .signedOut
    @State private var coordinator: SessionCoordinator?
    @State private var language = AVELanguageSelection()
    @State private var failure: String?
    @State private var showSettings = false
    @State private var showHistory = false
    /// Vrai quand le faux service de comptes est utilisé : un bandeau le dit sur l'écran de connexion.
    @State private var usingDevAccounts = false
    /// Historique gardé sur l'iPhone (`nil` si le dossier de l'app est inaccessible : l'app marche sans historique).
    @State private var store: (any ConversationStore)? = FileConversationStore.standard()
    /// Photos jointes, images et documents produits, gardés sur l'iPhone avec l'historique.
    @State private var mediaStore: (any MediaStore)? = FileMediaStore.standard()
    @State private var conversations: [StoredConversation] = []
    @State private var currentConversationID: UUID?

    // Réglages, gardés sur l'iPhone (UserDefaults).
    @AppStorage("onboarding.done") private var onboardingDone = false
    @AppStorage("language.code") private var languageCode = AVELanguage.french.rawValue
    @AppStorage("profile.firstName") private var firstName = ""
    @AppStorage("pref.autoPlay") private var autoPlay = true
    @AppStorage("pref.captions") private var captions = true
    @AppStorage("pref.haptics") private var haptics = true
    @AppStorage("pref.appearance") private var appearanceRaw = AVEAppearance.system.rawValue
    @AppStorage("pref.keepHistory") private var keepHistory = true

    private var appearance: AVEAppearance { AVEAppearance(rawValue: appearanceRaw) ?? .system }

    var body: some View {
        Group {
            if let failure {
                Text(failure).padding()
            } else if !onboardingDone {
                OnboardingView { chosen in
                    language = AVELanguageSelection(language: chosen)
                    onboardingDone = true
                }
            } else if case .signedIn(let kind) = authState, let coordinator, let session {
                signedIn(coordinator: coordinator, session: session, kind: kind)
            } else if case .signedIn = authState {
                // Connecté mais sans session (conversation en cours de création) : jamais l'écran de connexion.
                loadingMark
            } else if let signIn {
                SignInView(model: signIn)
                    .safeAreaInset(edge: .top) { if usingDevAccounts { devAccountsBanner } }
            } else {
                loadingMark
            }
        }
        .task { await bootstrap() }
        .onAppear {
            language = AVELanguageSelection(language: AVELanguage(rawValue: languageCode) ?? .french)
            conversations = store?.list() ?? []
            purgeMedia()
        }
        .onChange(of: language) { _, new in languageCode = new.language.rawValue }
        .onChange(of: autoPlay) { _, new in coordinator?.autoPlayInTextMode = new }
        .onChange(of: LaunchRequests.shared.voiceRequested) { _, _ in consumeVoiceRequest() }
        // Apparence du système par défaut (claire ou sombre), ou celle choisie dans les réglages.
        .environment(\.aveTheme, .ave)
        .preferredColorScheme(appearance.colorScheme)
    }

    // MARK: Écran connecté : conversation + historique

    private func signedIn(coordinator: SessionCoordinator, session: AuthSession, kind: AccountKind) -> some View {
        ZStack(alignment: .leading) {
            ChatView(coordinator: coordinator, language: $language, captions: $captions,
                     title: conversations.first(where: { $0.id == currentConversationID })?.title,
                     firstName: firstName.isEmpty ? nil : firstName, haptics: haptics,
                     onShowHistory: { showHistory = true },
                     onNewConversation: { Task { await newConversation(kind: kind) } },
                     onTranscriptChange: { record($0) })
            if showHistory {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showHistory = false }
                    .accessibilityLabel("Fermer l'historique")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)
                HistoryDrawer(
                    conversations: conversations, currentID: currentConversationID,
                    profileName: firstName.isEmpty ? "Mon compte" : firstName,
                    accountLabel: Self.label(of: kind),
                    onSelect: { conversation in Task { await open(conversation, kind: kind) } },
                    onNew: { Task { await newConversation(kind: kind) } },
                    onRename: rename, onDelete: delete,
                    onSettings: {
                        showHistory = false
                        showSettings = true
                    })
                .frame(width: 320)
                .frame(maxHeight: .infinity)
                .background(Color(.systemBackground).ignoresSafeArea())
                .gesture(DragGesture().onEnded { if $0.translation.width < -60 { showHistory = false } })
                .transition(.move(edge: .leading))
            }
        }
        .animation(.spring(duration: 0.3), value: showHistory)
        .sheet(isPresented: $showSettings) {
            SettingsView(session: session, coordinator: coordinator, accountKind: kind,
                         firstName: $firstName, language: $language, autoPlay: $autoPlay, captions: $captions,
                         haptics: $haptics,
                         appearance: Binding(get: { appearance }, set: { appearanceRaw = $0.rawValue }),
                         keepHistory: $keepHistory, onClearHistory: clearHistory, appIcons: AppIconChoice.ave)
        }
    }

    private static func label(of kind: AccountKind) -> String {
        switch kind {
        case .phone: return "Connecté avec votre numéro"
        case .apple: return "Connecté avec Apple"
        case .guest: return "Essai sans compte"
        }
    }

    // MARK: Historique

    /// Enregistre le fil dans l'historique (si le réglage le permet) : une conversation par session.
    private func record(_ messages: [ChatMessage]) {
        guard keepHistory, let store else { return }
        let stored = ConversationHistory.stored(from: messages)
        guard !stored.isEmpty else { return }
        let now = Date()
        if let index = conversations.firstIndex(where: { $0.id == currentConversationID }) {
            conversations[index].messages = stored
            conversations[index].updatedAt = now
            store.save(conversations[index])
        } else {
            let conversation = StoredConversation(title: ConversationHistory.title(for: stored), createdAt: now,
                                                  updatedAt: now, languageCode: language.language.rawValue,
                                                  messages: stored)
            currentConversationID = conversation.id
            conversations.insert(conversation, at: 0)
            store.save(conversation)
        }
    }

    private func rename(_ id: UUID, _ title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].title = title
        store?.save(conversations[index])
    }

    private func delete(_ id: UUID) {
        store?.delete(id: id)
        conversations.removeAll { $0.id == id }
        if currentConversationID == id { currentConversationID = nil }
        purgeMedia()
    }

    private func clearHistory() {
        store?.deleteAll()
        conversations = []
        currentConversationID = nil
        purgeMedia()
    }

    /// Efface les fichiers qu'aucune conversation ne cite plus : conversation effacée, historique désactivé, envoi
    /// abandonné. Ceux du fil affiché et des pièces jointes en cours d'envoi sont gardés.
    private func purgeMedia() {
        var keep = ConversationHistory.mediaNames(in: conversations)
        if let coordinator {
            keep.formUnion(coordinator.transcript.mediaNames)
            keep.formUnion(coordinator.attachmentDrafts.compactMap(\.localName))
        }
        mediaStore?.purge(keeping: keep)
    }

    /// « Nouvelle conversation » : un client = une session côté moteur ; on arrête l'ancienne et on en crée une neuve.
    private func newConversation(kind: AccountKind) async {
        showHistory = false
        currentConversationID = nil
        await rebuild(kind: kind, transcript: ChatTranscript())
    }

    /// Rouvre une conversation de l'historique : affichée telle quelle, l'assistant repart sans mémoire (et le dit).
    private func open(_ conversation: StoredConversation, kind: AccountKind) async {
        showHistory = false
        guard conversation.id != currentConversationID else { return }
        currentConversationID = conversation.id
        // D9 : la nouvelle session reçoit les derniers échanges ; l'avis « sans mémoire » n'apparaît que si le moteur
        // refuse le contexte (`SessionCoordinator`).
        await rebuild(kind: kind, transcript: ChatTranscript(restoring: conversation.messages))
    }

    private func rebuild(kind: AccountKind, transcript: ChatTranscript) async {
        guard let environment, let session else { return }
        if let old = coordinator { await old.stop() }
        coordinator = nil
        do { try buildCoordinator(env: environment, auth: session, kind: kind, transcript: transcript) } catch {
            failure = UserMessages.audioUnavailable
        }
        purgeMedia()
    }

    // MARK: Raccourcis (Siri, bouton Action)

    private func consumeVoiceRequest() {
        guard LaunchRequests.shared.voiceRequested, let coordinator else { return }
        LaunchRequests.shared.voiceRequested = false
        Task {
            await coordinator.start()  // sans effet si la session tourne déjà
            await coordinator.setMode(.voice)
        }
    }

    // MARK: Démarrage

    /// Pendant le démarrage : la naissance du logo (cercle → Afrique), puis son repos. Aucune attente ajoutée : l'écran
    /// suivant s'affiche dès qu'il est prêt (le HIG déconseille d'allonger un lancement pour montrer un logo).
    private var loadingMark: some View {
        AVELiveMark(phase: .idle, entrance: true)
            .frame(width: 150, height: 150)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Chargement")
    }

    /// Honnêteté envers les testeurs : rien n'est réellement vérifié et aucun SMS ne part.
    private var devAccountsBanner: some View {
        Label("Build de démonstration : aucun SMS n'est envoyé, le code est 000000.", systemImage: "hammer.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(AVEPalette.navy))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(AVEPalette.amber), in: .capsule)
            .padding(.top, 4)
    }

    private func bootstrap() async {
        guard session == nil else { return }
        do {
            let env = try AppEnvironment.load()
            let api = try makeAccountsAPI(env)
            let keychain = KeychainTokenStore()
            // Réinstallation : iOS a gardé l'ancienne session dans le trousseau ; on l'oublie, comme le reste de l'app.
            FreshInstall.purgeStaleSession(store: keychain)
            let auth = AuthSession(api: api, store: keychain)
            environment = env
            session = auth
            signIn = SignInViewModel(api: api, session: auth, attester: AppAttestGuestAttester(),
                                     defaultCountryCode: env.defaultCountryCode)
            for await state in auth.states {
                authState = state
                switch state {
                case .signedIn(let kind):
                    if coordinator == nil { try buildCoordinator(env: env, auth: auth, kind: kind, transcript: ChatTranscript()) }
                    coordinator?.accountKind = kind
                case .signedOut:
                    if let coordinator { await coordinator.stop() }
                    coordinator = nil
                    currentConversationID = nil
                    signIn?.back()
                }
            }
        } catch {
            failure = "Configuration invalide. Vérifiez l'adresse du serveur."
        }
    }

    private func makeAccountsAPI(_ env: AppEnvironment) throws -> any AccountsAPI {
        // Build « démo interface » : le réglage explicite l'emporte sur toute adresse.
        if env.demoAccounts {
            usingDevAccounts = true
            return DevAccountsAPI()
        }
        if let url = env.accountsURL {
            return try HTTPAccountsAPI(baseURL: url, allowInsecureLocalNetwork: env.allowInsecureLocal)
        }
        #if DEBUG
        usingDevAccounts = true
        return DevAccountsAPI()  // aucun service de comptes configuré : faux service, développement seulement
        #else
        throw AVEEndpointError.invalidURL
        #endif
    }

    private func buildCoordinator(env: AppEnvironment, auth: AuthSession, kind: AccountKind,
                                  transcript: ChatTranscript) throws {
        // Démo hors ligne : le moteur de démonstration ne demande aucun jeton (le service de comptes n'en délivre pas
        // sans moteur) ; la connexion au compte, elle, reste réelle.
        // `@Sendable` explicite : dans un « ? : », la fermeture n'hérite pas du type attendu et Swift 6 la refuse.
        let tokenProvider: AVETokenProvider
        if env.demoOffline {
            tokenProvider = { @Sendable in nil }
        } else {
            tokenProvider = auth.tokenProvider()
        }
        let configuration = AVEConfiguration(
            endpoint: env.endpoint, defaultLanguage: language.language,
            tokenProvider: tokenProvider, logger: .system, clientInfo: env.clientInfo, textDelta: true)
        let client = env.demoOffline
            ? configuration.makeClient(language: language.language, transportFactory: DemoEngineTransport.factory)
            : configuration.makeClient(language: language.language)
        // Fichiers et images : routes HTTP du moteur, même jeton court. Pas en démo hors ligne (aucun moteur).
        var media: MediaServices?
        if !env.demoOffline, let mediaStore,
           let files = try? AVEFilesClient(endpoint: env.endpoint, tokenProvider: tokenProvider) {
            media = MediaServices(files: files, store: mediaStore)
        }
        var sessionConfiguration = SessionCoordinator.Configuration()
        if env.demoOffline {
            sessionConfiguration.demoNotice = UserMessages.demoOffline
        } else {
            sessionConfiguration.demoNotice = env.demoEngine ? UserMessages.demoEngine : nil
        }
        // La conversation s'ouvre en mode texte, comme les assistants de référence ; le mode vocal est à un geste
        // (bouton de la barre de saisie, suggestion « Parler », raccourci Siri). Le micro n'est demandé qu'à ce moment-là.
        let new = SessionCoordinator(client: client, devices: try .system(), mode: .text,
                                     configuration: sessionConfiguration,
                                     activity: SessionLiveActivityController(), language: language.language,
                                     learningPreferences: UserDefaultsLearningPreferences(),
                                     accountKind: kind, transcript: transcript, media: media)
        new.autoPlayInTextMode = autoPlay
        coordinator = new
        consumeVoiceRequest()
    }
}
