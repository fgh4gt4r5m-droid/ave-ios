#if os(iOS)
import AVECore
import SwiftUI

/// Mode vocal plein écran, ouvert depuis la barre de saisie (comme le mode vocal de ChatGPT ou de Claude).
/// Même session que la conversation : « Terminer » coupe le micro et revient au texte, la connexion reste ouverte,
/// et ce qui a été dit s'affiche ensuite dans la conversation.
/// Proposition 2 : sous-titres en direct (ce que vous dites, ce qu'AVE répond, phrase par phrase) et micro coupé sans
/// quitter le mode vocal.
struct VoiceModeView: View {
    let coordinator: SessionCoordinator
    @Binding var language: AVELanguageSelection
    @Binding var captions: Bool
    let haptics: Bool
    @State private var showLanguages = false
    @Environment(\.aveTheme) private var theme

    private var state: OrbState { coordinator.orbState }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 8)
                FloatingVoiceOrbView(
                    state: state,
                    level: state == .speaking ? coordinator.playbackLevel : coordinator.micLevel,
                    diameter: captions ? 130 : 170,
                    onTap: { Task { await coordinator.interruptAssistant() } })
                .opacity(coordinator.micMuted ? 0.45 : 1)
                if captions {
                    liveCaptions
                } else {
                    stateText
                }
                Spacer(minLength: 8)
                if let notice = coordinator.notice {
                    NoticeBanner(text: notice, systemImage: "exclamationmark.triangle.fill",
                                 onDismiss: { coordinator.dismissNotice() })
                }
                controls
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background((theme.background ?? Color(.systemBackground)).ignoresSafeArea())
            .animation(.easeInOut(duration: 0.2), value: state)
            .animation(.easeInOut(duration: 0.2), value: captions)
            .sensoryFeedback(.impact(weight: .light), trigger: state) { _, new in haptics && (new == .listening || new == .thinking) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showLanguages = true } label: {
                        Label(LanguageCatalog.option(for: language.language)?.name ?? "Langue", systemImage: "globe")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .sheet(isPresented: $showLanguages) {
            LanguagePicker(selection: $language, options: coordinator.languageOptions)
                .presentationDetents([.medium, .large])
        }
    }

    /// État en grand (sans sous-titres), ou « Micro coupé ».
    private var stateText: some View {
        VStack(spacing: 8) {
            Text(coordinator.micMuted ? "Micro coupé" : state.label)
                .font(.title.bold())
                .contentTransition(.opacity)
            Text(coordinator.micMuted ? "AVE ne vous entend plus. Touchez Micro pour reprendre." : state.caption)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityHidden(true)  // déjà porté par l'orbe (valeur et aide VoiceOver)
    }

    /// Sous-titres : la dernière question et la dernière réponse, mises à jour phrase par phrase (`reply_text`).
    private var liveCaptions: some View {
        let messages = coordinator.transcript.messages.filter { $0.card == nil && $0.role != .system }
        let lastUser = messages.last(where: { $0.role == .user })
        let lastReply = messages.last(where: { $0.role == .assistant })
        return VStack(alignment: .leading, spacing: 12) {
            if let lastUser {
                Text("Vous : \(lastUser.text)").foregroundStyle(.secondary)
            }
            if let lastReply {
                Text("AVE : \(lastReply.isVoiceOnly ? "…" : lastReply.text)")
            }
            if lastUser == nil && lastReply == nil {
                Text(coordinator.micMuted ? "Micro coupé." : state.caption).foregroundStyle(.secondary)
            }
        }
        .font(.title3)
        .lineLimit(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Commandes en bas, comme le mode vocal de ChatGPT : de gros boutons ronds en verre, avec leur nom.
    private var controls: some View {
        GlassEffectContainer(spacing: 22) {
            HStack(spacing: 22) {
                roundControl(coordinator.micMuted ? "Micro coupé" : "Micro",
                             systemImage: coordinator.micMuted ? "mic.slash.fill" : "mic.fill",
                             active: coordinator.micMuted) {
                    Task { await coordinator.setMicMuted(!coordinator.micMuted) }
                }
                roundControl("Sous-titres", systemImage: "captions.bubble", active: captions) { captions.toggle() }
                if state == .speaking {
                    roundControl("Interrompre", systemImage: "stop.fill", active: false) {
                        Task { await coordinator.interruptAssistant() }
                    }
                    .transition(.opacity)
                }
                roundControl("Terminer", systemImage: "xmark", active: false) {
                    Task { await coordinator.setMode(.text) }
                }
            }
        }
    }

    private func roundControl(_ title: String, systemImage: String, active: Bool,
                              action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(active ? Color(.systemBackground) : Color.primary)
                    .frame(width: 60, height: 60)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(active ? Color.primary : nil)
            .accessibilityLabel(title)
            .accessibilityAddTraits(active ? .isSelected : [])
            Text(title).font(.footnote).foregroundStyle(.secondary).lineLimit(1).accessibilityHidden(true)
        }
    }
}
#endif
