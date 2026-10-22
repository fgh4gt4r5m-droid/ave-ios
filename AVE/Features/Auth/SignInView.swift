#if os(iOS)
import AVECore
import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

/// Écran de connexion : gros boutons avec icône (utilisateurs qui lisent peu), trois méthodes, aucune obligatoire.
public struct SignInView: View {
    @Bindable var model: SignInViewModel
    @Environment(\.aveTheme) private var theme
    @State private var appleNonce = ""

    public init(model: SignInViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("African Voice Engine").font(.largeTitle.bold()).multilineTextAlignment(.center)
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.warning)
                    .accessibilityLabel("Erreur : \(message)")
            }
            switch model.step {
            case .welcome: welcome
            case .phone: phone
            case .code(let masked): code(masked)
            }
            Spacer()
        }
        .padding()
        .disabled(model.isWorking)
        .overlay { if model.isWorking { ProgressView().accessibilityLabel("Chargement") } }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            bigButton("Avec mon numéro de téléphone", systemImage: "phone.fill") { model.choosePhone() }
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
            .frame(height: 50)
            if model.canUseGuest {
                bigButton("Essayer sans compte", systemImage: "person.fill.questionmark", prominent: false) {
                    Task { await model.continueAsGuest() }
                }
            }
        }
    }

    private var phone: some View {
        VStack(spacing: 14) {
            TextField("Numéro de téléphone", text: $model.phoneInput)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
            Picker("Recevoir le code par", selection: $model.channel) {
                Text("SMS").tag(OTPChannel.sms)
                Text("WhatsApp").tag(OTPChannel.whatsapp)
            }
            .pickerStyle(.segmented)
            bigButton("Recevoir le code", systemImage: "paperplane.fill") { Task { await model.sendCode() } }
            Button("Retour") { model.back() }.frame(minHeight: 44)
        }
    }

    private func code(_ masked: String) -> some View {
        VStack(spacing: 14) {
            Text("Code envoyé au \(masked)").font(.subheadline)
            TextField("Code reçu", text: $model.codeInput)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
            bigButton("Valider", systemImage: "checkmark.circle.fill") { Task { await model.verifyCode() } }
            Button("Changer de numéro") { model.back() }.frame(minHeight: 44)
        }
    }

    private func bigButton(_ title: String, systemImage: String, prominent: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(prominent ? theme.accent : .gray)
        .foregroundStyle(prominent ? theme.onAccent : .white)
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

/// Déconnexion et suppression du compte (la suppression dans l'app est exigée par l'App Store).
public struct AccountView: View {
    let session: AuthSession
    let coordinator: SessionCoordinator?
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    public init(session: AuthSession, coordinator: SessionCoordinator? = nil) {
        self.session = session
        self.coordinator = coordinator
    }

    public var body: some View {
        List {
            Section {
                Button("Se déconnecter") { Task { await session.signOut() } }.frame(minHeight: 44)
                Button("Supprimer mon compte", role: .destructive) { confirmDelete = true }.frame(minHeight: 44)
            }
            if let coordinator { LearningSettingsView(coordinator: coordinator) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.orange) }
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
#endif
