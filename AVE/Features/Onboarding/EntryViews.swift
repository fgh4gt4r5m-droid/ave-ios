#if os(iOS)
import AVECore
import SwiftUI

/// « Comment vous appelez-vous ? » (maquette « Entrée dans AVE », écran 4, validée le 2026-10-23). Un seul champ ; le
/// premier mot sert à saluer. Composants du système uniquement (exigence du propriétaire).
public struct EntryNameView: View {
    let suggestion: String?
    /// Enregistre le nom ; renvoie un message d'erreur, ou `nil` si c'est fait.
    let onSubmit: (String) async -> String?
    @State private var name = ""
    @State private var error: String?
    @State private var working = false
    @FocusState private var focused: Bool
    @Environment(\.aveTheme) private var theme

    public init(suggestion: String?, onSubmit: @escaping (String) async -> String?) {
        self.suggestion = suggestion
        self.onSubmit = onSubmit
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Comment vous appelez-vous ?") {
                    TextField("Nom complet", text: $name, prompt: Text("Prénom et nom"))
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.continue)
                        .focused($focused)
                        .onSubmit { Task { await submit() } }
                } footer: {
                    Text("AVE l'utilise pour vous saluer. Vous pourrez le changer dans les réglages.")
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(theme.warning) }
                }
            }
            .scrollContentBackground(.hidden)
            // Titre court : un grand titre d'iOS trop long serait coupé ; la question est dans l'en-tête du champ.
            .navigationTitle("Votre nom")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaBar(edge: .bottom) {
                Button {
                    Task { await submit() }
                } label: {
                    Text("Continuer").font(.headline).foregroundStyle(theme.onAccent).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(theme.accent)
                .controlSize(.large)
                .disabled(EntryFlow.cleanedName(name) == nil || working)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
            .overlay { if working { ProgressView().controlSize(.large) } }
        }
        .onAppear {
            if name.isEmpty, let suggestion { name = suggestion }
            focused = true
        }
    }

    private func submit() async {
        guard let cleaned = EntryFlow.cleanedName(name), !working else { return }
        working = true
        error = await onSubmit(cleaned)
        working = false
    }
}

/// « Avant de commencer » (écran 5) : trois points essentiels, puis deux engagements séparés, jamais acquis d'avance.
/// Des interrupteurs du système (le HIG les préfère aux cases à cocher sur iOS) ; « Commencer » s'active quand les deux
/// sont mis. L'aide à l'amélioration reste une demande à part, plus tard.
public struct EntryTermsView: View {
    /// Enregistre l'accord ; renvoie un message d'erreur, ou `nil` si c'est fait.
    let onAccept: () async -> String?
    @State private var adult = false
    @State private var accepted = false
    @State private var error: String?
    @State private var working = false
    @State private var reading: LegalDocument?
    @Environment(\.aveTheme) private var theme

    public init(onAccept: @escaping () async -> String?) {
        self.onAccept = onAccept
    }

    enum LegalDocument: String, Identifiable {
        case conditions, privacy
        var id: String { rawValue }
        var title: String { self == .conditions ? "Conditions d'utilisation" : "Politique de confidentialité" }
        var text: String { self == .conditions ? Terms.conditions : Terms.privacy }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Vos conversations restent sur votre iPhone. Vous pouvez tout effacer à tout moment.",
                          systemImage: "lock")
                    Label("AVE peut se tromper. Vérifiez les informations importantes.", systemImage: "info.circle")
                    Label("Pas de contenu sexuel, violent, haineux ou dangereux, ni de photo d'une personne sans son accord.",
                          systemImage: "hand.raised")
                }
                Section {
                    Toggle("J'ai \(Terms.minimumAge) ans ou plus", isOn: $adult)
                    Toggle(isOn: $accepted) {
                        Text("J'accepte les conditions d'utilisation et la politique de confidentialité")
                    }
                } footer: {
                    HStack(spacing: 16) {
                        Button("Conditions") { reading = .conditions }
                        Button("Confidentialité") { reading = .privacy }
                    }
                    .font(.footnote.weight(.semibold))
                    .tint(theme.accent)
                    .frame(minHeight: 44)
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(theme.warning) }
                }
            }
            .navigationTitle("Avant de commencer")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaBar(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        Task { await accept() }
                    } label: {
                        Text("Commencer").font(.headline).foregroundStyle(theme.onAccent).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(theme.accent)
                    .controlSize(.large)
                    .disabled(!(adult && accepted) || working)
                    Text("L'aide à l'amélioration d'AVE vous sera proposée plus tard, à part. Elle est facultative.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
            .overlay { if working { ProgressView().controlSize(.large) } }
            .sheet(item: $reading) { document in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Label(Terms.draftNotice, systemImage: "doc.badge.clock")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            RichText(text: document.text)
                        }
                        .padding(20)
                    }
                    .navigationTitle(document.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("OK") { reading = nil } }
                    }
                }
                .presentationDetents([.large])
            }
        }
    }

    private func accept() async {
        guard adult, accepted, !working else { return }
        working = true
        error = await onAccept()
        working = false
    }
}
#endif
