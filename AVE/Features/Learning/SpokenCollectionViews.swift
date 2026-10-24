#if os(iOS)
import SwiftUI

/// D13 (maquette « Apprendre nos langues », validée le 2026-10-24) : la phrase dite dans une langue qu'AVE ne transcrit
/// pas encore, dans le fil. Gardée (accord d'aide donné) : « Écrire ma phrase », puis la phrase écrite et un merci.
/// Pas gardée : on le dit, et on propose d'ouvrir les Réglages, sans insister. Composants du système uniquement.
struct SpokenCollectionRow: View {
    let collection: SpokenCollection
    let onWrite: () -> Void
    let onOpenSettings: (() -> Void)?
    @Environment(\.aveTheme) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Label(UserMessages.spokenPhrase(language: collection.languageName), systemImage: "mic.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            switch collection.state {
            case .awaitingText:
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(UserMessages.collectionKept(language: collection.languageName))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Écrire ma phrase", systemImage: "pencil", action: onWrite)
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                    }
                }
            case .sent(let text):
                // La phrase écrite, dans la bulle de la personne.
                Text(text)
                    .foregroundStyle(theme.userBubbleText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(theme.userBubble, in: .rect(cornerRadius: theme.cornerRadius))
                    .padding(.leading, 48)
                Text(UserMessages.collectionThanks(language: collection.languageName))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            case .notKept:
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(UserMessages.collectionNotKept(language: collection.languageName))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let onOpenSettings {
                            Button("Ouvrir les Réglages", action: onOpenSettings)
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// « Ce que vous avez dit » : feuille du système, un champ, Envoyer. Annuler ne garde que la voix, sans texte.
struct SpokenTextSheet: View {
    let languageName: String
    let onSend: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Votre phrase", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .autocorrectionDisabled()
                        .focused($focused)
                } header: {
                    Text("En \(languageName.lowercased())")
                } footer: {
                    Text("Écrivez la phrase comme vous l'avez dite, dans votre langue. Elle est rattachée à votre voix "
                         + "et relue par une personne avant de servir à l'apprentissage.")
                }
            }
            .navigationTitle("Ce que vous avez dit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Envoyer") {
                        onSend(trimmed)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty || trimmed.count > 1000)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Dans le mode vocal : au-dessus des boutons, « Écrire ma phrase » pour la dernière phrase gardée.
struct SpokenCollectionPrompt: View {
    let languageName: String
    let onWrite: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(UserMessages.collectionKept(language: languageName))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Écrire ma phrase", systemImage: "pencil", action: onWrite)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        }
    }
}
#endif
