#if os(iOS)
import AVECore
import SwiftUI

/// Demande d'aide à l'amélioration. « Non » et « Oui » ont le même poids visuel, rien n'est présélectionné,
/// la notice se lit à voix haute (automatiquement, sauf si VoiceOver est actif) et se réécoute.
public struct LearningPromptView: View {
    let prompt: LearningPrompt
    let onAnswer: (Bool) -> Void

    @State private var speaker = NoticeSpeaker()
    @Environment(\.aveTheme) private var theme

    public init(prompt: LearningPrompt, onAnswer: @escaping (Bool) -> Void) {
        self.prompt = prompt
        self.onAnswer = onAnswer
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(prompt.notice.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(prompt.notice.body).font(.body)
                if speaker.isAvailable(languageCode: prompt.notice.speechLanguageCode) {
                    Button {
                        speaker.speak(prompt.notice.spokenText, languageCode: prompt.notice.speechLanguageCode)
                    } label: {
                        Label("Écouter", systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                HStack(spacing: 12) {
                    answerButton(prompt.notice.yes, systemImage: "hand.thumbsup.fill", granted: true)
                    answerButton(prompt.notice.no, systemImage: "hand.thumbsdown.fill", granted: false)
                }
            }
            .padding()
        }
        .onAppear {
            if !NoticeSpeaker.screenReaderActive, speaker.isAvailable(languageCode: prompt.notice.speechLanguageCode) {
                speaker.speak(prompt.notice.spokenText, languageCode: prompt.notice.speechLanguageCode)
            }
        }
        .onDisappear { speaker.stop() }
    }

    private func answerButton(_ title: String, systemImage: String, granted: Bool) -> some View {
        Button {
            speaker.stop()
            onAnswer(granted)
        } label: {
            Label(title, systemImage: systemImage).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accent)
        .foregroundStyle(theme.onAccent)
    }
}

/// Réglages : état de l'aide, « Retirer mon aide », « Donner mon accord ».
public struct LearningSettingsView: View {
    let coordinator: SessionCoordinator
    @State private var confirmRevoke = false

    public init(coordinator: SessionCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        Section("Aider AVE à s'améliorer") {
            if !coordinator.learningOfferedToUser {
                Text("Cette option est réservée aux utilisateurs avec un compte.")
            } else if let status = coordinator.learning, status.available {
                if status.enabled {
                    Label("Vous aidez AVE.", systemImage: "heart.fill")
                    Button("Retirer mon aide", role: .destructive) { confirmRevoke = true }.frame(minHeight: 44)
                } else {
                    Text("Vous n'aidez pas AVE. L'application fonctionne exactement pareil.")
                    Button("Donner mon accord") { coordinator.presentLearningPrompt() }.frame(minHeight: 44)
                }
            } else {
                Text("Cette option n'est pas proposée pour votre accès.")
            }
            if let message = coordinator.learningMessage { Text(message).font(.footnote) }
        }
        .confirmationDialog("Retirer votre aide ? Ce qui a été gardé pour vous sera effacé.", isPresented: $confirmRevoke,
                            titleVisibility: .visible) {
            Button("Retirer mon aide", role: .destructive) { Task { await coordinator.revokeLearning() } }
            Button("Annuler", role: .cancel) {}
        }
    }
}

/// Correction facultative après un 👎 (1 000 caractères au maximum).
struct FeedbackCorrectionView: View {
    @State private var text = ""
    let onSend: (String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Qu'auriez-vous voulu entendre ? (facultatif)") {
                    TextEditor(text: $text).frame(minHeight: 120)
                    Text("\(text.count) / 1000").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Votre avis")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Passer") { onSend(nil) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Envoyer") { onSend(text) }.disabled(text.count > 1000)
                }
            }
        }
    }
}
#endif
