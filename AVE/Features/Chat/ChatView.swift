#if os(iOS)
import AVECore
import SwiftUI

/// Écran principal, construit comme les assistants conversationnels d'iOS (ChatGPT, Claude, Gemini) : la conversation
/// occupe tout l'écran et une barre de saisie en Liquid Glass flotte en bas (texte, envoi, mode vocal). Le mode vocal
/// s'ouvre en plein écran sur la MÊME session : le quitter coupe le micro, jamais la connexion.
public struct ChatView: View {
    let coordinator: SessionCoordinator
    @Binding var language: AVELanguageSelection
    /// Ouvre « Mon compte ». `nil` (app hôte comme WoYo ou TaGa) : pas de bouton.
    let onAccount: (() -> Void)?
    @State private var draft = ""
    @State private var showLanguages = false
    @State private var correctionTarget: Int?
    @State private var demoDismissed = false
    @FocusState private var composerFocused: Bool
    @Environment(\.aveTheme) private var theme

    public init(coordinator: SessionCoordinator, language: Binding<AVELanguageSelection>, onAccount: (() -> Void)? = nil) {
        self.coordinator = coordinator
        self._language = language
        self.onAccount = onAccount
    }

    public var body: some View {
        NavigationStack {
            messages
                .safeAreaBar(edge: .bottom) { composer }
                .navigationTitle("AVE")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showLanguages) {
            LanguagePicker(selection: $language, options: coordinator.languageOptions)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: Binding(get: { coordinator.learningPrompt != nil },
                                    set: { if !$0 { coordinator.dismissLearningPrompt() } })) {
            if let prompt = coordinator.learningPrompt {
                LearningPromptView(prompt: prompt) { granted in Task { await coordinator.answerLearning(granted: granted) } }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: Binding(get: { correctionTarget != nil }, set: { if !$0 { correctionTarget = nil } })) {
            FeedbackCorrectionView { correction in
                if let id = correctionTarget { Task { await coordinator.sendFeedback(messageID: id, rating: .down, correction: correction) } }
                correctionTarget = nil
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: voiceModeBinding) {
            VoiceModeView(coordinator: coordinator, language: $language)
        }
        .onChange(of: language) { _, new in
            Task { await coordinator.setLanguage(new.language) }
        }
        // `start()` est sans effet si la session tourne déjà. Pas d'arrêt dans `onDisappear` : iOS l'appelle aussi
        // quand le mode vocal plein écran recouvre cette vue, ce qui couperait la session. C'est le propriétaire du
        // coordinateur (l'app, ou l'app hôte) qui appelle `stop()` (déconnexion, fin de conversation).
        .task { await coordinator.start() }
    }

    // MARK: Barre d'outils (Liquid Glass fournie par le système)

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showLanguages = true } label: {
                Label(LanguageCatalog.option(for: language.language)?.name ?? "Langue", systemImage: "globe")
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityLabel("Langue : \(LanguageCatalog.option(for: language.language)?.name ?? "non choisie")")
        }
        if let onAccount {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mon compte", systemImage: "person.crop.circle", action: onAccount)
            }
        }
    }

    // MARK: Conversation

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    banners
                    if coordinator.transcript.messages.isEmpty {
                        emptyState
                    }
                    ForEach(coordinator.transcript.messages) { message in
                        MessageBubble(
                            message: message,
                            canReplay: coordinator.hasCachedAudio(for: message.id),
                            isReplaying: coordinator.replayingMessageID == message.id,
                            canFeedback: coordinator.canGiveFeedback,
                            feedbackSent: coordinator.feedbackGiven.contains(message.id),
                            onFeedback: { rating in
                                if rating == .up { Task { await coordinator.sendFeedback(messageID: message.id, rating: .up) } }
                                else { correctionTarget = message.id }
                            },
                            onReplay: { coordinator.replay(messageID: message.id) },
                            onConfirm: { coordinator.confirmAction(messageID: message.id) },
                            onDecline: { coordinator.declineAction(messageID: message.id) })
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .background((theme.background ?? Color(.systemBackground)).ignoresSafeArea())
            .onChange(of: coordinator.transcript.messages.count) { _, _ in
                if let last = coordinator.transcript.messages.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    /// Accueil d'une conversation vide : une phrase et un gros bouton « Parler », pour qui lit peu.
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)
            Text("Bonjour").font(.largeTitle.bold())
            Text("Parlez-moi ou écrivez-moi dans votre langue.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { openVoiceMode() } label: {
                Label("Parler", systemImage: "mic.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(theme.accent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    /// Avis à lire : état du moteur, erreur, connexion, apprentissage. Un seul à la fois, le plus important d'abord.
    @ViewBuilder private var banners: some View {
        if let text = coordinator.notice ?? coordinator.learningMessage ?? UserMessages.connection(coordinator.connection) {
            NoticeBanner(text: text, systemImage: "exclamationmark.triangle.fill", onDismiss: dismissBanner)
        } else if let demo = coordinator.demoNotice, !demoDismissed {
            NoticeBanner(text: demo, systemImage: "info.circle.fill", onDismiss: { demoDismissed = true })
        }
    }

    /// L'état de la connexion se ferme tout seul ; une erreur ou un message d'apprentissage se ferme à la main.
    private var dismissBanner: (() -> Void)? {
        if coordinator.notice != nil { return { coordinator.dismissNotice() } }
        if coordinator.learningMessage != nil { return { coordinator.dismissLearningMessage() } }
        return nil
    }

    // MARK: Barre de saisie

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var composer: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                if coordinator.supportsTextInput {
                    TextField("Votre message", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($composerFocused)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .frame(minHeight: 50)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 25))
                } else {
                    Text(UserMessages.textInputUnavailable)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                }
                if canSend {
                    roundButton(systemImage: "arrow.up", label: "Envoyer") { send() }
                } else {
                    roundButton(systemImage: "waveform", label: "Mode vocal") { openVoiceMode() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func roundButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.onAccent)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(theme.accent)
        .controlSize(.large)
        .accessibilityLabel(label)
    }

    private func send() {
        let message = draft
        draft = ""
        Task { await coordinator.sendText(message) }
    }

    // MARK: Mode vocal

    private func openVoiceMode() {
        composerFocused = false
        Task { await coordinator.setMode(.voice) }
    }

    /// Le mode vocal est affiché tant que la session est en mode voix (le micro refusé la repasse en texte : la vue se ferme).
    private var voiceModeBinding: Binding<Bool> {
        Binding(get: { coordinator.mode == .voice },
                set: { if !$0 { Task { await coordinator.setMode(.text) } } })
    }
}

/// Avis en tête de conversation : icône + texte + fermeture facultative.
struct NoticeBanner: View {
    let text: String
    let systemImage: String
    let onDismiss: (() -> Void)?
    @Environment(\.aveTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button("Fermer", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .padding(.vertical, -12)
            }
        }
        .padding(14)
        .background(theme.assistantBubble, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
#endif
