#if os(iOS)
import SwiftUI

/// L'historique en liste d'iOS (maquette « AVE tout natif », validée le 2026-10-24) : la colonne latérale d'un
/// `NavigationSplitView` (sur iPhone, on y revient par le bouton retour de la conversation ; sur iPad, c'est une barre
/// latérale). Sections par jour, recherche du système, sélection du système. Balayer vers la gauche : Supprimer,
/// Renommer (comme Mail) ; appui long : le même menu. Les conversations sont gardées sur cet iPhone seulement.
public struct HistoryList: View {
    let conversations: [StoredConversation]
    @Binding var selection: UUID?
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void

    @State private var query = ""
    @State private var renaming: StoredConversation?
    @State private var newTitle = ""
    @State private var deleting: StoredConversation?

    public init(conversations: [StoredConversation], selection: Binding<UUID?>,
                onRename: @escaping (UUID, String) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.conversations = conversations
        self._selection = selection
        self.onRename = onRename
        self.onDelete = onDelete
    }

    public var body: some View {
        let found = ConversationHistory.search(query, in: conversations)
        List(selection: $selection) {
            ForEach(ConversationHistory.grouped(found, now: .now)) { group in
                Section(group.section.rawValue) {
                    ForEach(group.items) { conversation in
                        row(conversation)
                    }
                }
            }
            if !conversations.isEmpty {
                Section {} footer: { Text("Gardées sur cet iPhone seulement.") }
            }
        }
        .searchable(text: $query, prompt: "Rechercher")
        .overlay {
            if conversations.isEmpty {
                ContentUnavailableView("Aucune conversation", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Vos conversations apparaîtront ici."))
            } else if found.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .alert("Renommer la conversation", isPresented: Binding(get: { renaming != nil },
                                                                 set: { if !$0 { renaming = nil } })) {
            TextField("Titre", text: $newTitle)
            Button("Annuler", role: .cancel) { renaming = nil }
            Button("Renommer") {
                let cleaned = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if let renaming, !cleaned.isEmpty { onRename(renaming.id, cleaned) }
                renaming = nil
            }
        }
        .confirmationDialog("Supprimer cette conversation ?", isPresented: Binding(get: { deleting != nil },
                                                                                  set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { conversation in
            Button("Supprimer", role: .destructive) {
                onDelete(conversation.id)
                deleting = nil
            }
            Button("Annuler", role: .cancel) { deleting = nil }
        } message: { _ in
            Text("Elle sera effacée de cet iPhone.")
        }
    }

    private func row(_ conversation: StoredConversation) -> some View {
        LabeledContent {
            Text(ConversationHistory.shortDate(conversation.updatedAt, now: .now))
        } label: {
            Text(conversation.title).lineLimit(1)
        }
        .tag(conversation.id)
        .swipeActions(edge: .trailing) {
            // La suppression se confirme (validé) : le balayage ouvre la confirmation du système.
            Button("Supprimer", systemImage: "trash", role: .destructive) { deleting = conversation }
            Button("Renommer", systemImage: "pencil") { startRenaming(conversation) }
        }
        .contextMenu {
            Button("Renommer", systemImage: "pencil") { startRenaming(conversation) }
            Button("Supprimer", systemImage: "trash", role: .destructive) { deleting = conversation }
        }
    }

    private func startRenaming(_ conversation: StoredConversation) {
        newTitle = conversation.title
        renaming = conversation
    }
}
#endif
