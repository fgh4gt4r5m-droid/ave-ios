#if os(iOS)
import AVECore
import SwiftUI

/// Mode vocal plein écran, ouvert depuis la barre de saisie (comme le mode vocal de ChatGPT ou de Claude).
/// Même session que la conversation : « Terminer » coupe le micro et revient au texte, la connexion reste ouverte,
/// et ce qui a été dit s'affiche ensuite dans la conversation.
/// Proposition 2 : sous-titres en direct (ce que vous dites, ce qu'AVE répond, phrase par phrase) et micro coupé sans
/// quitter le mode vocal. Écrans épurés (validés le 2026-10-23) : plein écran sombre, la langue en haut, trois boutons
/// ronds de 64 points, « Terminer » seul en rouge à droite (comme raccrocher), et la lumière douce sur le pourtour.
struct VoiceModeView: View {
    let coordinator: SessionCoordinator
    @Binding var language: AVELanguageSelection
    @Binding var captions: Bool
    let haptics: Bool
    /// D13 : la phrase gardée qu'on écrit (feuille « Ce que vous avez dit »).
    @State private var writing: Int?
    @Environment(\.aveTheme) private var theme

    private var state: OrbState { coordinator.orbState }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 8)
                voiceMark
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
                // D13 : la dernière phrase gardée, à écrire (rien ne s'ouvre de force).
                if let id = coordinator.pendingCollectionID,
                   let collection = coordinator.transcript.message(id)?.collection {
                    SpokenCollectionPrompt(languageName: collection.languageName,
                                           unsupported: collection.languageUnsupported) { writing = id }
                }
                controls
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    Color.black
                    AmbientGlow(mood: glowMood, level: glowMood == .speaking ? coordinator.playbackLevel : coordinator.micLevel)
                }
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: glowMood)
            }
            .animation(.easeInOut(duration: 0.2), value: state)
            .animation(.easeInOut(duration: 0.2), value: captions)
            .sensoryFeedback(.impact(weight: .light), trigger: state) { _, new in haptics && (new == .listening || new == .thinking) }
            // Le même menu de titre que la conversation : la langue en sous-titre, choisie d'un toucher sur « AVE ».
            .navigationTitle("AVE")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(LanguageTitleMenu(language: $language, options: coordinator.languageOptions, onRename: nil))
        }
        // Toujours sombre, comme un appel : la lumière se voit, rien d'autre ne bouge.
        .preferredColorScheme(.dark)
        .sheet(item: Binding(get: { writing.map(WritingTarget.init) }, set: { writing = $0?.id })) { target in
            SpokenTextSheet(languageName: coordinator.transcript.message(target.id)?.collection?.languageName ?? "") { text in
                Task { await coordinator.sendSpokenText(messageID: target.id, text: text) }
            }
        }
    }

    /// Le logo vivant remplace l'orbe : au repos l'Afrique en barres ; en écoute un cercle, en réflexion une onde, en
    /// parole une bulle, et les barres suivent le son réel (micro ou voix d'AVE). Toucher pendant que l'assistant parle
    /// l'interrompt, comme l'orbe. L'état est dit par le texte et par VoiceOver, jamais par le seul dessin.
    private var voiceMark: some View {
        Button { Task { await coordinator.interruptAssistant() } } label: {
            AVELiveMark(phase: AVEMarkPhase(orb: state),
                        level: state == .speaking ? coordinator.playbackLevel : coordinator.micLevel)
                .frame(width: captions ? 200 : 260, height: captions ? 200 : 260)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!state.isInteractive)
        .opacity(state == .unavailable ? 0.35 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Assistant vocal")
        .accessibilityValue(state.label)
        .accessibilityHint(state.hint)
        .accessibilityAddTraits(state.isInteractive ? .isButton : [])
        .accessibilityAction {
            // L'élément regroupé ne transmet pas toujours le toucher double au bouton : on le rend explicite.
            guard state.isInteractive else { return }
            Task { await coordinator.interruptAssistant() }
        }
        .onChange(of: state) { _, new in
            // Annonce les changements utiles ; la parole de l'assistant s'entend déjà.
            if new == .listening || new == .thinking || new == .unavailable {
                AccessibilityNotification.Announcement(new.label).post()
            }
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

    /// La lumière : froide quand on parle, chaude quand AVE parle ; rien au repos, en réflexion ou micro coupé.
    private var glowMood: AmbientGlow.Mood? {
        switch state {
        case .listening: return coordinator.micMuted ? nil : .listening
        case .speaking: return .speaking
        default: return nil
        }
    }

    /// Trois boutons ronds de 64 points en verre (on les touche sans regarder). Couper la voix d'AVE : toucher le symbole.
    private var controls: some View {
        GlassEffectContainer(spacing: 28) {
            HStack(spacing: 28) {
                roundControl(coordinator.micMuted ? "Micro coupé" : "Couper le micro",
                             systemImage: coordinator.micMuted ? "mic.slash.fill" : "mic.fill",
                             active: coordinator.micMuted) {
                    Task { await coordinator.setMicMuted(!coordinator.micMuted) }
                }
                roundControl("Sous-titres", systemImage: "captions.bubble", active: captions) { captions.toggle() }
                // Terminer : le seul bouton rouge, à droite, comme raccrocher dans Téléphone.
                roundControl("Terminer", systemImage: "xmark", active: false, tint: .red) {
                    Task { await coordinator.setMode(.text) }
                }
            }
        }
    }

    private func roundControl(_ title: String, systemImage: String, active: Bool, tint: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint != nil || active ? Color.white : Color.primary)
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(tint ?? (active ? Color.white.opacity(0.35) : Color.white.opacity(0.14)))
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
/// Identifiant de feuille (un `Int` n'est pas `Identifiable`).
struct WritingTarget: Identifiable {
    let id: Int
}
#endif
