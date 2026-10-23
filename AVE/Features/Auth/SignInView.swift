#if os(iOS)
import AVECore
import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

/// Écran de connexion : trois méthodes, aucune obligatoire. Gros boutons avec icône (utilisateurs qui lisent peu),
/// composants système (Liquid Glass, Sign in with Apple officiel), une seule action principale par étape.
public struct SignInView: View {
    @Bindable var model: SignInViewModel
    @Environment(\.aveTheme) private var theme
    @State private var appleNonce = ""
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var fieldFocused: Bool

    public init(model: SignInViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch model.step {
                case .welcome: welcome
                case .phone: phone
                case .code(let masked): code(masked)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background((theme.background ?? Color(.systemBackground)).ignoresSafeArea())
            .toolbar {
                if model.step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Retour", systemImage: "chevron.backward") { model.back() }
                    }
                }
            }
            .disabled(model.isWorking)
            .overlay { if model.isWorking { ProgressView().controlSize(.large).accessibilityLabel("Chargement") } }
        }
    }

    // MARK: Accueil

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
                Text("AVE").font(.system(size: 52, weight: .bold, design: .rounded))
                Text("African Voice Engine").font(.headline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("AVE, African Voice Engine")
            Text("Parlez à l'assistant dans votre langue.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Spacer()
            errorLabel
            VStack(spacing: 12) {
                primaryButton("Avec mon numéro de téléphone", systemImage: "phone.fill") { model.choosePhone() }
                SignInWithAppleButton(.continue) { request in
                    appleNonce = Self.randomNonce()
                    request.requestedScopes = []  // ni nom ni e-mail : on n'en a pas besoin
                    request.nonce = Self.sha256Hex(appleNonce)
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                              let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                            model.appleFailed()
                            return
                        }
                        let nonce = appleNonce
                        Task { await model.signInWithApple(identityToken: token, rawNonce: nonce) }
                    case .failure(let error):
                        if (error as? ASAuthorizationError)?.code == .canceled { model.appleCancelled() } else { model.appleFailed() }
                    }
                }
                // HIG : bouton noir sur fond clair, blanc sur fond sombre.
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 54)
                .clipShape(.capsule)  // même forme que les boutons Liquid Glass voisins
                if model.canUseGuest {
                    Button { Task { await model.continueAsGuest() } } label: {
                        Label("Essayer sans compte", systemImage: "person.fill.questionmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
            Text("En continuant, vous acceptez les conditions d'utilisation et la politique de confidentialité.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    // MARK: Numéro

    private var phone: some View {
        Form {
            Section {
                TextField("Numéro de téléphone", text: $model.phoneInput, prompt: Text("+224 6xx xx xx xx"))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .font(.title3)
                    .focused($fieldFocused)
            } footer: {
                Text("Nous envoyons un code à 6 chiffres pour vérifier que c'est bien vous.")
            }
            Section("Recevoir le code par") {
                Picker("Recevoir le code par", selection: $model.channel) {
                    Text("SMS").tag(OTPChannel.sms)
                    Text("WhatsApp").tag(OTPChannel.whatsapp)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if let message = model.errorMessage {
                Section { errorText(message) }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Votre numéro")
        .safeAreaBar(edge: .bottom) {
            primaryButton("Recevoir le code", systemImage: "paperplane.fill") { Task { await model.sendCode() } }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        .onAppear { fieldFocused = true }
    }

    // MARK: Code

    private func code(_ masked: String) -> some View {
        Form {
            Section {
                TextField("Code reçu", text: $model.codeInput, prompt: Text("000000"))
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                    .tracking(8)
                    .multilineTextAlignment(.center)
                    .focused($fieldFocused)
            } header: {
                Text("Envoyé au \(masked)")
            } footer: {
                if let seconds = model.resendAfterSeconds {
                    Text("Pas reçu ? Vous pourrez redemander un code dans \(seconds) s.")
                }
            }
            if let message = model.errorMessage {
                Section { errorText(message) }
            }
            Section {
                Button("Changer de numéro") { model.back() }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Code reçu")
        .safeAreaBar(edge: .bottom) {
            primaryButton("Valider", systemImage: "checkmark") { Task { await model.verifyCode() } }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        .onAppear { fieldFocused = true }
    }

    // MARK: Éléments communs

    @ViewBuilder private var errorLabel: some View {
        if let message = model.errorMessage { errorText(message) }
    }

    private func errorText(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(theme.warning)
            .accessibilityLabel("Erreur : \(message)")
    }

    /// Action principale d'une étape : Liquid Glass « proéminent », teinté par la charte, texte bleu nuit sur le bleu
    /// (le blanc sur ce bleu ne fait que 2,7:1).
    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(theme.accent)
        .controlSize(.large)
    }

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess { bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) } }
        return Data(bytes).base64EncodedString()
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// « Mon compte » : aide à l'amélioration, déconnexion, suppression du compte (exigée par l'App Store).
public struct AccountView: View {
    let session: AuthSession
    let coordinator: SessionCoordinator?
    let accountKind: AccountKind?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    public init(session: AuthSession, coordinator: SessionCoordinator? = nil, accountKind: AccountKind? = nil) {
        self.session = session
        self.coordinator = coordinator
        self.accountKind = accountKind
    }

    public var body: some View {
        NavigationStack {
            List {
                if let accountKind {
                    Section {
                        Label(Self.description(of: accountKind), systemImage: Self.symbol(of: accountKind))
                    }
                }
                if let coordinator { LearningSettingsView(coordinator: coordinator) }
                Section {
                    Button("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right") {
                        Task { await session.signOut() }
                    }
                    Button("Supprimer mon compte", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } footer: {
                    if let errorMessage { Text(errorMessage).foregroundStyle(.orange) }
                }
                Section {
                    LabeledContent("Version", value: Self.appVersion)
                }
            }
            .navigationTitle("Mon compte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                }
            }
            .confirmationDialog("Supprimer définitivement votre compte ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    Task {
                        // Efface d'abord côté moteur ce qui a été gardé pour l'apprentissage : le service de comptes ne peut pas le faire.
                        if let coordinator, coordinator.learning?.enabled == true { await coordinator.revokeLearning() }
                        do { try await session.deleteAccount() } catch {
                            errorMessage = AuthMessages.message(for: (error as? AuthError) ?? .unavailable)
                        }
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    private static func description(of kind: AccountKind) -> String {
        switch kind {
        case .phone: return "Connecté avec votre numéro"
        case .apple: return "Connecté avec Apple"
        case .guest: return "Essai sans compte"
        }
    }

    private static func symbol(of kind: AccountKind) -> String {
        switch kind {
        case .phone: return "phone.fill"
        case .apple: return "apple.logo"
        case .guest: return "person.fill.questionmark"
        }
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
#endif
