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

/// Assemble configuration, connexion, audio réel et coordinateur de session.
struct RootView: View {
    @State private var environment: AppEnvironment?
    @State private var session: AuthSession?
    @State private var signIn: SignInViewModel?
    @State private var authState: AuthSession.State = .signedOut
    @State private var coordinator: SessionCoordinator?
    @State private var language = AVELanguageSelection()
    @State private var failure: String?
    @State private var showAccount = false
    /// Vrai quand le faux service de comptes est utilisé : un bandeau le dit sur l'écran de connexion.
    @State private var usingDevAccounts = false

    var body: some View {
        Group {
            if let failure {
                Text(failure).padding()
            } else if case .signedIn(let kind) = authState, let coordinator, let session {
                ChatView(coordinator: coordinator, language: $language, onAccount: { showAccount = true },
                         onNewConversation: { Task { await startNewConversation(kind: kind) } })
                    .sheet(isPresented: $showAccount) {
                        AccountView(session: session, coordinator: coordinator, accountKind: kind)
                    }
            } else if case .signedIn = authState {
                // Connecté mais sans session (nouvelle conversation en cours de création) : jamais l'écran de connexion.
                ProgressView()
            } else if let signIn {
                SignInView(model: signIn)
                    .safeAreaInset(edge: .top) { if usingDevAccounts { devAccountsBanner } }
            } else {
                ProgressView()
            }
        }
        .task { await bootstrap() }
        // Apparence du système (claire ou sombre), comme les assistants de référence : plus de bleu nuit imposé.
        .environment(\.aveTheme, .ave)
    }

    /// « Nouvelle conversation » : un client = une session côté moteur ; on arrête l'ancienne et on en crée une neuve.
    private func startNewConversation(kind: AccountKind) async {
        guard let environment, let session, let old = coordinator else { return }
        await old.stop()
        coordinator = nil
        do { try buildCoordinator(env: environment, auth: session, kind: kind) } catch {
            failure = UserMessages.audioUnavailable
        }
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
            let auth = AuthSession(api: api, store: KeychainTokenStore())
            environment = env
            session = auth
            signIn = SignInViewModel(api: api, session: auth, attester: AppAttestGuestAttester(),
                                     defaultCountryCode: env.defaultCountryCode)
            for await state in auth.states {
                authState = state
                switch state {
                case .signedIn(let kind):
                    if coordinator == nil { try buildCoordinator(env: env, auth: auth, kind: kind) }
                    coordinator?.accountKind = kind
                case .signedOut:
                    if let coordinator { await coordinator.stop() }
                    coordinator = nil
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

    private func buildCoordinator(env: AppEnvironment, auth: AuthSession, kind: AccountKind) throws {
        let configuration = AVEConfiguration(
            endpoint: env.endpoint, defaultLanguage: language.language,
            tokenProvider: auth.tokenProvider(), logger: .system, clientInfo: env.clientInfo)
        let client = configuration.makeClient(language: language.language)
        var sessionConfiguration = SessionCoordinator.Configuration()
        sessionConfiguration.demoNotice = env.demoEngine ? UserMessages.demoEngine : nil
        // La conversation s'ouvre en mode texte, comme les assistants de référence ; le mode vocal est à un geste
        // (bouton de la barre de saisie, gros bouton « Parler » de l'accueil). Le micro n'est demandé qu'à ce moment-là.
        coordinator = SessionCoordinator(client: client, devices: try .system(), mode: .text,
                                         configuration: sessionConfiguration,
                                         activity: SessionLiveActivityController(), language: language.language,
                                         learningPreferences: UserDefaultsLearningPreferences(),
                                         accountKind: kind)
    }
}
