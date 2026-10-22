#if os(iOS)
import SwiftUI

/// Écran de conversation : bulles, cartes d'action, orbe vocal, bascule voix ↔ texte.
public struct ChatView: View {
    let coordinator: SessionCoordinator
    @Binding var language: AVELanguageSelection
    @State private var draft = ""
    @State private var showLanguages = false

    public init(coordinator: SessionCoordinator, language: Binding<AVELanguageSelection>) {
        self.coordinator = coordinator
        self._language = language
    }

    public var body: some View {
        VStack(spacing: 0) {
            banner
            messages
            Divider()
            controls
        }
        .sheet(isPresented: $showLanguages) {
            LanguagePicker(selection: $language)
        }
        .task { await coordinator.start() }
        .onDisappear { Task { await coordinator.stop() } }
    }

    @ViewBuilder private var banner: some View {
        let text = coordinator.notice ?? UserMessages.connection(coordinator.connection)
        if let text {
            HStack {
                Text(text).font(.footnote)
                Spacer()
                if coordinator.notice != nil {
                    Button("Fermer", action: coordinator.dismissNotice).font(.footnote).frame(minHeight: 44)
                }
            }
            .padding(.horizontal)
            .background(.yellow.opacity(0.2))
            .accessibilityElement(children: .combine)
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(coordinator.transcript.messages) { message in
                        MessageBubble(
                            message: message,
                            canReplay: coordinator.hasCachedAudio(for: message.id),
                            isReplaying: coordinator.replayingMessageID == message.id,
                            onReplay: { coordinator.replay(messageID: message.id) },
                            onConfirm: { coordinator.confirmAction(messageID: message.id) },
                            onDecline: { coordinator.declineAction(messageID: message.id) })
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: coordinator.transcript.messages.count) { _, _ in
                if let last = coordinator.transcript.messages.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Button { showLanguages = true } label: {
                    Label(LanguageCatalog.option(for: language.language)?.name ?? "Langue", systemImage: "globe")
                        .frame(minHeight: 44)
                }
                Spacer()
                Picker("Mode", selection: modeBinding) {
                    Text("Voix").tag(SessionMode.voice)
                    Text("Texte").tag(SessionMode.text)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }
            if coordinator.mode == .voice {
                FloatingVoiceOrbView(
                    state: coordinator.orbState,
                    level: coordinator.orbState == .speaking ? coordinator.playbackLevel : coordinator.micLevel,
                    onTap: { Task { await coordinator.interruptAssistant() } })
            } else {
                textField
            }
        }
        .padding()
    }

    private var modeBinding: Binding<SessionMode> {
        Binding(get: { coordinator.mode }, set: { new in Task { await coordinator.setMode(new) } })
    }

    @ViewBuilder private var textField: some View {
        if coordinator.supportsTextInput {
            HStack {
                TextField("Votre message", text: $draft).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                Button("Envoyer") {
                    coordinator.sendText(draft)
                    draft = ""
                }
                .frame(minHeight: 44)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } else {
            Text(UserMessages.textInputUnavailable)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(UserMessages.textInputUnavailable)
        }
    }
}
#endif
