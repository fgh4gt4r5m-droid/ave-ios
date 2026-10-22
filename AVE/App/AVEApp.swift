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

/// Assemble configuration, jeton (Keychain), audio réel et coordinateur de session.
struct RootView: View {
    @State private var coordinator: SessionCoordinator?
    @State private var language = AVELanguageSelection()
    @State private var failure: String?

    var body: some View {
        Group {
            if let coordinator {
                ChatView(coordinator: coordinator, language: $language)
            } else if let failure {
                Text(failure).padding()
            } else {
                ProgressView()
            }
        }
        .task { build() }
        .environment(\.aveTheme, .ave)
        .background((AVETheme.ave.background ?? .black).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func build() {
        guard coordinator == nil else { return }
        do {
            let environment = try AppEnvironment.load()
            let tokens = KeychainTokenStore()
            let configuration = AVEConfiguration(
                endpoint: environment.endpoint,
                defaultLanguage: language.language,
                tokenProvider: { tokens.readToken() },
                logger: .system,
                clientInfo: environment.clientInfo)
            let client = configuration.makeClient(language: language.language)
            coordinator = SessionCoordinator(client: client, devices: try .system())
        } catch {
            failure = "Configuration invalide. Vérifiez l'adresse du serveur."
        }
    }
}
