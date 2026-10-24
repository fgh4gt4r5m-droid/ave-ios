#if os(iOS)
import AVECore
import SwiftUI
import UIKit

/// Apparence choisie dans les réglages (« Automatique » suit l'iPhone).
public enum AVEAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "Automatique"
        case .light: return "Clair"
        case .dark: return "Sombre"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Réglages, liste système regroupée (proposition 2) : profil, conversation, apparence, données, compte, à propos.
/// Remplace « Mon compte » : la déconnexion et la suppression du compte (exigée par l'App Store) y sont.
public struct SettingsView: View {
    let session: AuthSession
    let coordinator: SessionCoordinator?
    let accountKind: AccountKind?
    @Binding var firstName: String
    @Binding var language: AVELanguageSelection
    @Binding var autoPlay: Bool
    @Binding var captions: Bool
    @Binding var haptics: Bool
    @Binding var appearance: AVEAppearance
    @Binding var keepHistory: Bool
    let onClearHistory: () -> Void
    /// Icônes de l'app au choix (vide : pas de section, par exemple dans une app hôte qui intègre AVEKit).
    let appIcons: [AppIconChoice]

    @State private var confirmDelete = false
    @State private var confirmClear = false
    @State private var showLanguages = false
    @State private var errorMessage: String?
    @State private var currentIcon: String?
    @State private var iconError: String?
    @Environment(\.dismiss) private var dismiss

    public init(session: AuthSession, coordinator: SessionCoordinator?, accountKind: AccountKind?,
                firstName: Binding<String>, language: Binding<AVELanguageSelection>, autoPlay: Binding<Bool>,
                captions: Binding<Bool>, haptics: Binding<Bool>, appearance: Binding<AVEAppearance>,
                keepHistory: Binding<Bool>, onClearHistory: @escaping () -> Void, appIcons: [AppIconChoice] = []) {
        self.session = session
        self.coordinator = coordinator
        self.accountKind = accountKind
        self._firstName = firstName
        self._language = language
        self._autoPlay = autoPlay
        self._captions = captions
        self._haptics = haptics
        self._appearance = appearance
        self._keepHistory = keepHistory
        self.onClearHistory = onClearHistory
        self.appIcons = appIcons
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Prénom (facultatif)", text: $firstName)
                        .textContentType(.givenName)
                    if let accountKind {
                        Label(Self.description(of: accountKind), systemImage: Self.symbol(of: accountKind))
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Le prénom sert seulement à vous saluer ; il reste sur cet iPhone.")
                }

                Section("Conversation") {
                    Button { showLanguages = true } label: {
                        LabeledContent("Langue", value: LanguageCatalog.option(for: language.language)?.name ?? "—")
                    }
                    .foregroundStyle(.primary)
                    Toggle(isOn: $autoPlay) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lire les réponses à voix haute")
                            Text("Aussi quand j'écris").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Sous-titres en mode vocal", isOn: $captions)
                    Toggle("Vibrations", isOn: $haptics)
                }

                Section("Apparence") {
                    Picker("Thème", selection: $appearance) {
                        ForEach(AVEAppearance.allCases) { Text($0.label).tag($0) }
                    }
                }

                if !appIcons.isEmpty { appIconSection }

                Section {
                    Toggle("Garder l'historique sur cet iPhone", isOn: $keepHistory)
                    Button("Effacer l'historique", role: .destructive) { confirmClear = true }
                } header: {
                    Text("Données")
                } footer: {
                    Text("L'historique n'est jamais envoyé : il est gardé sur cet iPhone et effacé avec l'app.")
                }

                if let coordinator { LearningSettingsView(coordinator: coordinator) }

                Section {
                    Button("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right") {
                        Task { await session.signOut() }
                    }
                    Button("Supprimer mon compte", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } header: {
                    Text("Compte")
                } footer: {
                    if let errorMessage { Text(errorMessage).foregroundStyle(.orange) }
                }

                Section("AVE") {
                    LabeledContent("Version", value: Self.appVersion)
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                }
            }
            .sheet(isPresented: $showLanguages) {
                LanguagePicker(selection: $language, options: coordinator?.languageOptions ?? LanguageCatalog.builtIn)
                    .presentationDetents([.medium, .large])
            }
            .confirmationDialog("Effacer tout l'historique de cet iPhone ?", isPresented: $confirmClear,
                                titleVisibility: .visible) {
                Button("Effacer", role: .destructive, action: onClearHistory)
                Button("Annuler", role: .cancel) {}
            }
            .confirmationDialog("Supprimer définitivement votre compte ?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    Task {
                        // Efface d'abord côté moteur ce qui a été gardé pour l'apprentissage : le service de comptes ne peut pas le faire.
                        if let coordinator, coordinator.learning?.enabled == true { await coordinator.revokeLearning() }
                        do {
                            try await session.deleteAccount()
                            onClearHistory()  // un compte supprimé ne laisse pas son historique sur l'iPhone
                        } catch {
                            errorMessage = AuthMessages.message(for: (error as? AuthError) ?? .unavailable)
                        }
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    // MARK: Icône de l'app

    /// Liste à coche du système (maquette « AVE tout natif », validée le 2026-10-24) : on touche une ligne, l'icône
    /// change sur l'écran d'accueil (iOS affiche lui-même une confirmation). Les aperçus sont des images, sans cadre.
    private var appIconSection: some View {
        Section {
            Picker("Icône de l'app", selection: Binding(
                get: { appIcons.first { $0.alternateName == currentIcon }?.id ?? "" },
                set: { id in if let choice = appIcons.first(where: { $0.id == id }) { choose(choice) } }
            )) {
                ForEach(appIcons) { choice in
                    Label {
                        Text(choice.title)
                    } icon: {
                        Image(choice.previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .clipShape(.rect(cornerRadius: 10, style: .continuous))
                    }
                    .tag(choice.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Icône de l'app")
        } footer: {
            if let iconError {
                Text(iconError).foregroundStyle(.orange)
            } else {
                Text("En mode sombre, l'icône passe sur fond bleu nuit ; en mode teinté, iOS la colore.")
            }
        }
        .onAppear { currentIcon = UIApplication.shared.alternateIconName }
    }

    private func choose(_ choice: AppIconChoice) {
        guard choice.alternateName != currentIcon, UIApplication.shared.supportsAlternateIcons else { return }
        iconError = nil
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(choice.alternateName)
                currentIcon = choice.alternateName
            } catch {
                iconError = "L'icône n'a pas pu être changée. Réessayez."
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
