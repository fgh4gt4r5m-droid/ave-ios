#if os(iOS)
import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    let canReplay: Bool
    let isReplaying: Bool
    let onReplay: () -> Void
    let onConfirm: () -> Void
    let onDecline: () -> Void

    @Environment(\.aveTheme) private var theme

    var body: some View {
        switch message.role {
        case .system:
            Label(message.text, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(theme.warning)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Information : \(message.text)")
        case .user:
            bubble(text: message.text, background: theme.userBubble, foreground: theme.userBubbleText)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Vous : \(message.text)")
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                if let card = message.card {
                    ActionCardView(card: card, onConfirm: onConfirm, onDecline: onDecline)
                } else {
                    let text = message.isVoiceOnly ? "Réponse vocale" : message.text
                    bubble(text: text, background: theme.assistantBubble, foreground: theme.assistantBubbleText)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Assistant : \(text)\(message.status == .interrupted ? ", interrompu" : "")")
                    if message.status == .interrupted {
                        Text("Interrompu").font(.caption).foregroundStyle(.secondary)
                    }
                    if canReplay {
                        Button(action: onReplay) {
                            Label(isReplaying ? "Lecture…" : "Réécouter", systemImage: "play.circle")
                                .frame(minHeight: 44)
                        }
                        .disabled(isReplaying)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bubble(text: String, background: Color, foreground: Color) -> some View {
        Text(text)
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(background, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
    }
}

struct ActionCardView: View {
    let card: ActionCard
    let onConfirm: () -> Void
    let onDecline: () -> Void

    @Environment(\.aveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Action proposée : \(card.name)", systemImage: "bolt.fill").font(.headline)
            if !card.summary.isEmpty { Text(card.summary).font(.subheadline) }
            switch card.status {
            case .awaitingConfirmation:
                HStack(spacing: 12) {
                    Button("Confirmer", action: onConfirm).buttonStyle(.borderedProminent)
                    Button("Refuser", role: .cancel, action: onDecline).buttonStyle(.bordered)
                }
                .frame(minHeight: 44)
            case .confirmed:
                Label("Confirmée", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .declined:
                Label("Refusée", systemImage: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(theme.assistantBubble, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        .accessibilityElement(children: .contain)
    }
}
#endif
