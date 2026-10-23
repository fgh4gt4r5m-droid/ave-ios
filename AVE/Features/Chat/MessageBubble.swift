#if os(iOS)
import AVECore
import SwiftUI

/// Un message de la conversation, mis en forme comme dans les assistants d'iOS : la personne dans une bulle discrète à
/// droite, l'assistant en texte libre pleine largeur (plus lisible pour les longues réponses), ses actions juste dessous.
struct MessageBubble: View {
    let message: ChatMessage
    /// « Lire à voix haute » possible (audio gardé, ou synthèse à la demande par le moteur).
    let canReadAloud: Bool
    let isReplaying: Bool
    var canFeedback = false
    var feedbackSent = false
    var onFeedback: (FeedbackRating) -> Void = { _ in }
    let onReplay: () -> Void
    let onConfirm: () -> Void
    let onDecline: () -> Void
    /// « Réessayer » (réponse de l'assistant) : renvoie la question précédente.
    var onRetry: (() -> Void)?
    /// « Modifier » (question de la personne) : la remet dans la barre de saisie.
    var onEdit: (() -> Void)?

    @Environment(\.aveTheme) private var theme
    @State private var copied = false

    var body: some View {
        switch message.role {
        case .system:
            // Texte en couleur normale, seule l'icône porte l'avertissement (lisible en clair comme en sombre).
            Label {
                Text(message.text).foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warning)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Information : \(message.text)")
        case .user:
            Text(message.text)
                .foregroundStyle(theme.userBubbleText)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(theme.userBubble, in: .rect(cornerRadius: theme.cornerRadius))
                // Appui long : menu natif d'iOS (copier, modifier, partager), comme ChatGPT et Claude.
                .contextMenu { userMenu }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 48)
                .accessibilityLabel("Vous : \(message.text)")
        case .assistant:
            if let card = message.card {
                ActionCardView(card: card, onConfirm: onConfirm, onDecline: onDecline)
            } else {
                assistant
            }
        }
    }

    private var assistant: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.isVoiceOnly {
                Label("Réponse vocale", systemImage: "waveform")
                    .foregroundStyle(.secondary)
            } else {
                RichText(text: message.text)
                    .foregroundStyle(theme.assistantBubbleText)
                    .contextMenu { assistantMenu }
            }
            if message.status == .interrupted {
                Label("Interrompu", systemImage: "hand.raised.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if message.status != .streaming { actions }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    /// Copier, lire à voix haute, avis : icônes seules sous la réponse, comme ChatGPT et Claude, chacune avec un libellé
    /// VoiceOver et 44 pt de cible.
    @ViewBuilder private var actions: some View {
        HStack(spacing: 0) {
            if !message.isVoiceOnly, !message.text.isEmpty {
                iconButton(copied ? "checkmark" : "doc.on.doc", label: copied ? "Copié" : "Copier") {
                    UIPasteboard.general.string = message.text
                    copied = true
                }
            }
            if canReadAloud {
                iconButton(isReplaying ? "speaker.wave.2.fill" : "speaker.wave.2",
                           label: isReplaying ? "Lecture en cours" : "Lire à voix haute", action: onReplay)
                    .disabled(isReplaying)
            }
            if !message.isVoiceOnly, !message.text.isEmpty {
                ShareLink(item: message.text) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Partager")
            }
            if let onRetry {
                iconButton("arrow.clockwise", label: "Réessayer", action: onRetry)
            }
            if canFeedback, message.utteranceID != nil {
                if feedbackSent {
                    Text(UserMessages.feedbackThanks).font(.footnote).foregroundStyle(.secondary).padding(.leading, 8)
                } else {
                    iconButton("hand.thumbsup", label: "Bonne réponse") { onFeedback(.up) }
                    iconButton("hand.thumbsdown", label: "Mauvaise réponse") { onFeedback(.down) }
                }
            }
        }
        .padding(.leading, -12)  // aligne l'icône (et non sa zone tactile) sur le texte
    }

    @ViewBuilder private var userMenu: some View {
        Button("Copier", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
        if let onEdit { Button("Modifier", systemImage: "pencil", action: onEdit) }
        ShareLink("Partager", item: message.text)
    }

    @ViewBuilder private var assistantMenu: some View {
        Button("Copier", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
        if canReadAloud { Button("Lire à voix haute", systemImage: "speaker.wave.2", action: onReplay) }
        ShareLink("Partager", item: message.text)
        if let onRetry { Button("Réessayer", systemImage: "arrow.clockwise", action: onRetry) }
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var accessibilityText: String {
        let text = message.isVoiceOnly ? "Réponse vocale" : message.text
        return "Assistant : \(text)\(message.status == .interrupted ? ", interrompu" : "")"
    }
}

/// Action proposée par l'assistant. `confirm: true` : rien ne part sans « Confirmer » (la voix seule ne valide jamais).
struct ActionCardView: View {
    let card: ActionCard
    let onConfirm: () -> Void
    let onDecline: () -> Void

    @Environment(\.aveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Action proposée : \(card.name)", systemImage: "bolt.fill")
                .font(.headline)
            if !card.summary.isEmpty {
                Text(card.summary).font(.subheadline).foregroundStyle(.secondary)
            }
            switch card.status {
            case .awaitingConfirmation:
                HStack(spacing: 10) {
                    Button { onConfirm() } label: {
                        Text("Confirmer").foregroundStyle(theme.onAccent).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    Button(role: .cancel) { onDecline() } label: {
                        Text("Refuser").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            case .confirmed:
                Label("Confirmée", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .declined:
                Label("Refusée", systemImage: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(theme.assistantBubble, in: .rect(cornerRadius: theme.cornerRadius))
        .accessibilityElement(children: .contain)
    }
}
#endif
