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

    /// Connexion (maquette d'entrée validée le 2026-10-23) : le logo au repos, un titre, et les deux connexions au même
    /// niveau (exigé par Apple) ; « Essayer sans compte » reste discret.
    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            AVELiveMark(phase: .idle).frame(width: 96, height: 96)
            VStack(spacing: 8) {
                Text("Connectez-vous")
                    .font(.title.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                // Ce qu'un compte apporte vraiment, sans rien promettre de plus.
                Text("Avec votre numéro ou votre compte Apple. Vous pourrez supprimer votre compte à tout moment.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            errorLabel
            VStack(spacing: 12) {
                primaryButton("Continuer avec mon numéro", systemImage: "phone.fill") { model.choosePhone() }
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
                        // Code d'autorisation : permet au service de révoquer le jeton Apple si le compte est supprimé.
                        let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
                        Task { await model.signInWithApple(identityToken: token, rawNonce: nonce, authorizationCode: code) }
                    case .failure(let error):
                        if (error as? ASAuthorizationError)?.code == .canceled { model.appleCancelled() } else { model.appleFailed() }
                    }
                }
                // HIG : bouton noir sur fond clair, blanc sur fond sombre.
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(.capsule)  // même forme et même hauteur que le bouton du numéro : même poids
                if model.canUseGuest {
                    Button("Essayer sans compte") { Task { await model.continueAsGuest() } }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .tint(theme.accent)
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

    /// L'indicatif se choisit (proposé d'avance) : on ne tape que son numéro. Un numéro collé avec « + » reste accepté.
    private var phone: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    countryMenu
                    Divider()
                    TextField("Numéro de téléphone", text: $model.phoneInput, prompt: Text("6xx xx xx xx"))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .font(.title3)
                        .focused($fieldFocused)
                }
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

    private var countryMenu: some View {
        let selected = PhoneCountry.forDialCode(model.countryCode)
        let code = model.countryCode ?? ""
        return Menu {
            Picker("Indicatif", selection: countryBinding) {
                ForEach(PhoneCountry.all) { country in
                    Text("\(country.flag) \(country.name)  +\(country.dialCode)").tag(country.dialCode)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selected.map { "\($0.flag) +\(code)" } ?? (code.isEmpty ? "Pays" : "+\(code)"))
                    .font(.title3.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .frame(minHeight: 44)
        }
        .accessibilityLabel("Indicatif")
        .accessibilityValue(selected.map { "\($0.name), plus \(code)" } ?? (code.isEmpty ? "aucun" : "plus \(code)"))
    }

    private var countryBinding: Binding<String> {
        Binding(get: { model.countryCode ?? "" }, set: { model.countryCode = $0 })
    }

    // MARK: Code

    /// Six cases ; le code reçu par SMS se propose au-dessus du clavier (`oneTimeCode`) et il est validé dès qu'il est
    /// complet, sans bouton. Un vrai champ texte, invisible, reçoit la saisie : VoiceOver et le collage marchent.
    private func code(_ masked: String) -> some View {
        VStack(spacing: 20) {
            Text("Envoyé au \(masked)")
                .foregroundStyle(.secondary)
            codeBoxes
            resendLine
            if let message = model.errorMessage { errorText(message) }
            Button("Changer de numéro") { model.back() }
                .font(.headline)
                .frame(minHeight: 44)
                .tint(theme.accent)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .navigationTitle("Code reçu")
        .onAppear { fieldFocused = true }
        .onChange(of: model.codeInput) { _, _ in
            if model.codeDidChange() { Task { await model.verifyCode() } }
        }
    }

    private var codeBoxes: some View {
        let digits = Array(model.codeInput)
        return ZStack {
            HStack(spacing: 8) {
                ForEach(0..<SignInViewModel.codeLength, id: \.self) { index in
                    Text(index < digits.count ? String(digits[index]) : "")
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .frame(width: 46, height: 56)
                        .background(theme.assistantBubble, in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(fieldFocused && index == min(digits.count, SignInViewModel.codeLength - 1)
                                              ? theme.accent : Color.clear, lineWidth: 2)
                        }
                }
            }
            .accessibilityHidden(true)
            TextField("Code reçu", text: $model.codeInput)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($fieldFocused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(height: 56)
        }
        .contentShape(.rect)
        .onTapGesture { fieldFocused = true }
    }

    /// Décompte avant de pouvoir redemander un code, puis « Renvoyer un code ».
    private var resendLine: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let seconds = model.resendCountdown(at: context.date) {
                Text("Pas reçu ? Nouveau code dans \(seconds) s.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button("Renvoyer un code") { Task { await model.resendCode() } }
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
                    .tint(theme.accent)
            }
        }
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
#endif
