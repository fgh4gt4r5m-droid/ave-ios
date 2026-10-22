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

    var body: some View {
        Group {
            if let failure {
                Text(failure).padding()
            } else if case .signedIn = authState, let coordinator, let session {
                ChatView(coordinator: coordinator, language: $language)
                    .overlay(alignment: .topTrailing) {
                        Button { showAccount = true } label: {
                            Image(systemName: "person.crop.circle").font(.title2).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Mon compte")
                    }
                    .sheet(isPresented: $showAccount) { AccountView(session: session, coordinator: coordinator) }
            } else if let signIn {
                SignInView(model: signIn)
            } else {
                ProgressView()
            }
        }
        .task { await bootstrap() }
        .environment(\.aveTheme, .ave)
        .background((AVETheme.ave.background ?? .black).ignoresSafeArea())
        .preferredColorScheme(.dark)
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
                case .signedIn: if coordinator == nil { try buildCoordinator(env: env, auth: auth) }
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
        if let url = env.accountsURL {
            return try HTTPAccountsAPI(baseURL: url, allowInsecureLocalNetwork: env.allowInsecureLocal)
        }
        #if DEBUG
        return DevAccountsAPI()  // aucun service de comptes configuré : faux service, développement seulement
        #else
        throw AVEEndpointError.invalidURL
        #endif
    }

    private func buildCoordinator(env: AppEnvironment, auth: AuthSession) throws {
        let configuration = AVEConfiguration(
            endpoint: env.endpoint, defaultLanguage: language.language,
            tokenProvider: auth.tokenProvider(), logger: .system, clientInfo: env.clientInfo)
        let client = configuration.makeClient(language: language.language)
        coordinator = SessionCoordinator(client: client, devices: try .system(),
                                         activity: SessionLiveActivityController(), language: language.language,
                                         learningPreferences: UserDefaultsLearningPreferences())
    }
}
