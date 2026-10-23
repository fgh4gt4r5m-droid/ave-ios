#if os(iOS)
import AVECore
import SwiftUI

/// Mode vocal plein écran, ouvert depuis la barre de saisie (comme le mode vocal de ChatGPT ou de Claude).
/// Même session que la conversation : « Terminer » coupe le micro et revient au texte, la connexion reste ouverte,
/// et ce qui a été dit s'affiche ensuite dans la conversation.
struct VoiceModeView: View {
    let coordinator: SessionCoordinator
    @Binding var language: AVELanguageSelection
    @State private var showLanguages = false
    @Environment(\.aveTheme) private var theme

    private var state: OrbState { coordinator.orbState }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 12)
                lastExchange
                FloatingVoiceOrbView(
                    state: state,
                    level: state == .speaking ? coordinator.playbackLevel : coordinator.micLevel,
                    diameter: 170,
                    onTap: { Task { await coordinator.interruptAssistant() } })
                VStack(spacing: 8) {
                    Text(state.label)
                        .font(.title.bold())
                        .contentTransition(.opacity)
                    Text(state.caption)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .accessibilityHidden(true)  // déjà porté par l'orbe (valeur et aide VoiceOver)
                Spacer(minLength: 12)
                if let notice = coordinator.notice {
                    NoticeBanner(text: notice, systemImage: "exclamationmark.triangle.fill",
                                 onDismiss: { coordinator.dismissNotice() })
                }
                if state == .speaking {
                    Button { Task { await coordinator.interruptAssistant() } } label: {
                        Label("Interrompre", systemImage: "stop.fill").frame(minHeight: 44)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background((theme.background ?? Color(.systemBackground)).ignoresSafeArea())
            .animation(.easeInOut(duration: 0.2), value: state)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showLanguages = true } label: {
                        Label(LanguageCatalog.option(for: language.language)?.name ?? "Langue", systemImage: "globe")
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Terminer", systemImage: "xmark") { Task { await coordinator.setMode(.text) } }
                }
            }
        }
        .sheet(isPresented: $showLanguages) {
            LanguagePicker(selection: $language, options: coordinator.languageOptions)
                .presentationDetents([.medium, .large])
        }
    }

    /// Dernier message, en petit : on sait ce que l'assistant a compris ou répond, sans quitter le mode vocal.
    @ViewBuilder private var lastExchange: some View {
        if let last = coordinator.transcript.messages.last(where: { $0.role != .system && $0.card == nil }) {
            Text(last.isVoiceOnly ? "Réponse vocale" : last.text)
                .font(.title3)
                .foregroundStyle(last.role == .user ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(last.role == .user ? "Vous avez dit : \(last.text)" : "Assistant : \(last.text)")
        }
    }
}
#endif
