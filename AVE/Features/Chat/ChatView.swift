#if os(iOS)
import AVECore
import SwiftUI

/// Écran principal, aux standards des assistants d'iOS (ChatGPT, Claude, Gemini ; décision du 2026-10-23) :
/// - barre du haut système : compte à gauche, titre « AVE » + langue au centre (comme le choix du modèle), nouvelle
///   conversation à droite (crayon) ;
/// - accueil sobre : une question, rien d'autre ;
/// - UNE barre de saisie Liquid Glass en bas : le champ, et dedans un seul bouton rond qui est « mode vocal » quand le
///   champ est vide et « envoyer » dès qu'on écrit ; la mention sur l'état du service en petit dessous (comme « ChatGPT
///   peut faire des erreurs ») ;
/// - le mode vocal s'ouvre en plein écran sur la MÊME session.
public struct ChatView: View {
    let coordinator: SessionCoordinator
    @Binding var language: AVELanguageSelection
    /// Ouvre « Mon compte ». `nil` (app hôte comme WoYo ou TaGa) : pas de bouton.
    let onAccount: (() -> Void)?
    /// Repart d'une conversation vide (nouvelle session côté moteur). `nil` : pas de bouton.
    let onNewConversation: (() -> Void)?
    @State private var draft = ""
    @State private var showLanguages = false
    @State private var correctionTarget: Int?
    @FocusState private var composerFocused: Bool
    @Environment(\.aveTheme) private var theme

    public init(coordinator: SessionCoordinator, language: Binding<AVELanguageSelection>,
                onAccount: (() -> Void)? = nil, onNewConversation: (() -> Void)? = nil) {
        self.coordinator = coordinator
        self._language = language
        self.onAccount = onAccount
        self.onNewConversation = onNewConversation
    }

    public var body: some View {
        NavigationStack {
            messages
                .safeAreaBar(edge: .bottom) { composer }
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
        // coordinateur (l'app, ou l'app hôte) qui appelle `stop()` (déconnexion, nouvelle conversation).
        .task { await coordinator.start() }
    }

    // MARK: Barre du haut (Liquid Glass fournie par le système)

    private var languageName: String {
        LanguageCatalog.option(for: language.language)?.name ?? "Langue"
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if let onAccount {
            ToolbarItem(placement: .topBarLeading) {
                Button("Mon compte", systemImage: "person.crop.circle", action: onAccount)
            }
        }
        ToolbarItem(placement: .principal) {
            // Comme le choix du modèle dans ChatGPT : le nom de l'app, et dessous ce qu'on peut changer (la langue).
            Button { showLanguages = true } label: {
                VStack(spacing: 0) {
                    Text("AVE").font(.headline)
                    HStack(spacing: 3) {
                        Text(languageName)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Langue : \(languageName)")
            .accessibilityHint("Choisir la langue de la conversation.")
        }
        if let onNewConversation {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Nouvelle conversation", systemImage: "square.and.pencil", action: onNewConversation)
                    .disabled(coordinator.transcript.messages.isEmpty)
            }
        }
    }

    // MARK: Conversation

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    statusLine
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
            .overlay { if coordinator.transcript.messages.isEmpty { emptyState } }
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

    /// Accueil d'une conversation vide, comme les assistants de référence : une question centrée, sans autre bouton
    /// (le mode vocal est le bouton rond de la barre de saisie).
    private var emptyState: some View {
        Text("Que puis-je faire pour vous ?")
            .font(.title2.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .allowsHitTesting(false)
    }

    /// Une ligne discrète en tête : erreur à lire (fermable), sinon état de la connexion. Rien quand tout va bien.
    @ViewBuilder private var statusLine: some View {
        if let text = coordinator.notice ?? coordinator.learningMessage {
            NoticeBanner(text: text, systemImage: "exclamationmark.triangle.fill", onDismiss: {
                if coordinator.notice != nil { coordinator.dismissNotice() } else { coordinator.dismissLearningMessage() }
            })
        } else if let text = UserMessages.connection(coordinator.connection) {
            Label(text, systemImage: "wifi.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: Barre de saisie

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 4) {
                if coordinator.supportsTextInput {
                    TextField("Message", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($composerFocused)
                        .padding(.leading, 18)
                        .padding(.vertical, 14)
                } else {
                    Text(UserMessages.textInputUnavailable)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                actionButton
                    .padding(.trailing, 4)
                    .padding(.bottom, 2)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
            if let demo = coordinator.demoNotice {
                Text(demo)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.15), value: canSend)
    }

    /// Un seul bouton rond, dans la barre : « mode vocal » quand le champ est vide, « envoyer » dès qu'on écrit.
    private var actionButton: some View {
        Button {
            if canSend { send() } else { openVoiceMode() }
        } label: {
            Image(systemName: canSend ? "arrow.up" : "waveform")
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.onAccent)
                .frame(width: 38, height: 38)
                .background(theme.accent, in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(canSend ? "Envoyer" : "Mode vocal")
        .accessibilityHint(canSend ? "" : "Parler avec l'assistant.")
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

/// Avis à lire en tête de conversation : icône + texte + fermeture.
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
