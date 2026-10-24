#if os(iOS)
import AVECore
import SwiftUI

/// Premier lancement (proposition 2) : une promesse claire, puis le choix de la langue AVANT la connexion, poussé dans
/// une pile de navigation du système. Composants d'iOS uniquement (maquette « AVE tout natif », validée le 2026-10-24) :
/// liste à coche, langues pas encore prêtes grisées « Bientôt » comme dans le menu de titre (statut de la liste de
/// repli : le serveur n'est pas encore joint à ce moment-là).
public struct OnboardingView: View {
    let onFinish: (AVELanguage) -> Void
    @State private var choosing = false
    @State private var selection: AVELanguage = .french
    @Environment(\.aveTheme) private var theme

    public init(onFinish: @escaping (AVELanguage) -> Void) {
        self.onFinish = onFinish
    }

    private var options: [LanguageOption] {
        LanguageCatalog.builtIn.filter { $0.language != .auto }
    }

    public var body: some View {
        NavigationStack {
            welcome
                .safeAreaBar(edge: .bottom) {
                    primaryButton("Commencer") { choosing = true }
                }
                .navigationDestination(isPresented: $choosing) { languages }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(theme.accent)
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    /// Bienvenue (maquette d'entrée validée le 2026-10-23) : le logo naît puis se pose au repos, le mot AVE s'écrit
    /// dessous, sur le même axe, puis le slogan. C'est le seul écran qui montre le slogan.
    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            // Naissance du logo (cercle → Afrique), puis repos : l'Afrique dessinée par les barres.
            AVELiveMark(phase: .idle, entrance: true).frame(width: 170, height: 170)
            // Le mot attend la fin de la naissance du logo, puis s'écrit.
            AVEWordmark(width: 210, delay: 1.2)
            Text("NOS LANGUES · VOTRE AVENIR")
                .font(.caption.weight(.medium))
                .tracking(2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Nos langues, votre avenir")
            Spacer()
            Text("Parlez ou écrivez.\nAVE vous répond à voix haute et par écrit.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background((theme.background ?? Color(.systemBackground)).ignoresSafeArea())
    }

    private var languages: some View {
        Form {
            Section {
                Picker("Langue", selection: $selection) {
                    ForEach(options) { option in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name)
                            if let native = option.nativeName {
                                Text(native).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .tag(option.language)
                        .badge(option.isAvailable ? nil : Text("Bientôt"))
                        .selectionDisabled(!option.isAvailable)
                        .foregroundStyle(option.isAvailable ? Color.primary : Color.secondary)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("Vous pourrez la changer à tout moment, d'un toucher sur le titre de la conversation.")
            }
        }
        .navigationTitle("Votre langue")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaBar(edge: .bottom) {
            primaryButton("Continuer") { onFinish(selection) }
        }
    }
}
#endif
