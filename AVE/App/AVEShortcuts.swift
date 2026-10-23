import AppIntents
import Observation

/// « Parler à AVE » : ouvre l'app directement en mode vocal. Proposé à Siri (« Dis Siri, parle à AVE »), à Spotlight,
/// à l'app Raccourcis et donc au bouton Action (Réglages › Bouton Action › Raccourci). Le widget et la commande du
/// Centre de contrôle viendront dans l'extension, avec la même intention.
struct StartVoiceConversationIntent: AppIntent {
    static var title: LocalizedStringResource { "Parler à AVE" }
    static var description: IntentDescription { IntentDescription("Ouvre AVE en mode vocal.") }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        LaunchRequests.shared.voiceRequested = true
        return .result()
    }
}

struct AVEShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartVoiceConversationIntent(),
                    phrases: ["Parler à \(.applicationName)", "Parle à \(.applicationName)",
                              "Ouvre \(.applicationName) en mode vocal"],
                    shortTitle: "Parler à AVE",
                    systemImageName: "waveform")
    }
}

/// Demandes venues de l'extérieur de l'app (raccourcis), lues par l'écran racine dès qu'une session est prête.
@MainActor
@Observable
final class LaunchRequests {
    static let shared = LaunchRequests()
    var voiceRequested = false
}
