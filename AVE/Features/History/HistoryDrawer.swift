#if os(iOS)
import SwiftUI

/// Barre latérale de l'historique, comme ChatGPT : recherche, nouvelle conversation, conversations regroupées par date,
/// profil et réglages en bas. Appui long sur une conversation : renommer, supprimer. Les conversations sont gardées sur
/// cet iPhone seulement.
public struct HistoryDrawer: View {
    let conversations: [StoredConversation]
    let currentID: UUID?
    let profileName: String
    let accountLabel: String
    let onSelect: (StoredConversation) -> Void
    let onNew: () -> Void
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void
    let onSettings: () -> Void

    @State private var query = ""
    @State private var renaming: StoredConversation?
    @State private var newTitle = ""
    @Environment(\.aveTheme) private var theme

    public init(conversations: [StoredConversation], currentID: UUID?, profileName: String, accountLabel: String,
                onSelect: @escaping (StoredConversation) -> Void, onNew: @escaping () -> Void,
                onRename: @escaping (UUID, String) -> Void, onDelete: @escaping (UUID) -> Void,
                onSettings: @escaping () -> Void) {
        self.conversations = conversations
        self.currentID = currentID
        self.profileName = profileName
        self.accountLabel = accountLabel
        self.onSelect = onSelect
        self.onNew = onNew
        self.onRename = onRename
        self.onDelete = onDelete
        self.onSettings = onSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Rechercher", text: $query)
                    .submitLabel(.search)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))

            Button(action: onNew) {
                Label("Nouvelle conversation", systemImage: "square.and.pencil")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            list

            Text("Gardées sur cet iPhone seulement.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

            Divider()
            Button(action: onSettings) {
                HStack(spacing: 10) {
                    Text(String(profileName.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(theme.onAccent)
                        .frame(width: 36, height: 36)
                        .background(theme.accent, in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(profileName).font(.headline)
                        Text(accountLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "gearshape").font(.title3).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Réglages, \(profileName)")
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .alert("Renommer la conversation", isPresented: Binding(get: { renaming != nil },
                                                                 set: { if !$0 { renaming = nil } })) {
            TextField("Titre", text: $newTitle)
            Button("Annuler", role: .cancel) { renaming = nil }
            Button("Renommer") {
                if let renaming, !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    onRename(renaming.id, newTitle.trimmingCharacters(in: .whitespaces))
                }
                renaming = nil
            }
        }
    }

    @ViewBuilder private var list: some View {
        let found = ConversationHistory.search(query, in: conversations)
        if conversations.isEmpty {
            ContentUnavailableView("Aucune conversation", systemImage: "bubble.left.and.bubble.right",
                                   description: Text("Vos conversations apparaîtront ici."))
                .frame(maxHeight: .infinity)
        } else if found.isEmpty {
            ContentUnavailableView.search(text: query)
                .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(ConversationHistory.grouped(found, now: .now)) { group in
                        Text(group.section.rawValue)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.items) { conversation in
                            row(conversation)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func row(_ conversation: StoredConversation) -> some View {
        Button { onSelect(conversation) } label: {
            Text(conversation.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 10)
                .background(conversation.id == currentID ? Color(.secondarySystemBackground) : .clear,
                            in: .rect(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(conversation.id == currentID ? .isSelected : [])
        .contextMenu {
            Button("Renommer", systemImage: "pencil") {
                newTitle = conversation.title
                renaming = conversation
            }
            Button("Supprimer", systemImage: "trash", role: .destructive) { onDelete(conversation.id) }
        }
    }
}
#endif
