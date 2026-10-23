#if os(iOS)
import AVFoundation
import Observation

/// Le micro de dictée de la barre de saisie (écrans épurés validés ; reconnaissance d'Apple sur l'iPhone, décision du
/// propriétaire du 2026-10-23). Un toucher : on dicte, le texte s'écrit dans la barre à la suite de ce qui y est déjà ;
/// un second toucher : fini. Rien ne part tant que la personne n'a pas touché Envoyer.
@MainActor
@Observable
final class DictationController {
    private(set) var isListening = false
    @ObservationIgnored private let recognizer = DictationRecognizer()

    /// Démarre la dictée. `update` reçoit le texte complet de la barre ; renvoie un message à montrer en cas d'échec.
    func start(current: String, update: @escaping @MainActor (String) -> Void) async -> String? {
        guard !isListening else { return nil }
        guard await DictationRecognizer.authorize() else { return UserMessages.dictationDenied }
        guard await AVAudioApplication.requestRecordPermission() else { return UserMessages.microphoneDenied }
        let base = current.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try recognizer.start { [weak self] event in
                Task { @MainActor in self?.handle(event, base: base, update: update) }
            }
        } catch {
            return UserMessages.dictationUnavailable
        }
        isListening = true
        return nil
    }

    /// Second toucher : le micro se coupe, le texte définitif arrive juste après.
    func finish() {
        recognizer.finish()
    }

    /// Envoi, mode vocal, sortie de l'écran : on arrête tout de suite, ce qui est écrit reste.
    func cancel() {
        recognizer.stop()
        isListening = false
    }

    private func handle(_ event: DictationRecognizer.Event, base: String, update: @MainActor (String) -> Void) {
        guard isListening else { return }
        switch event {
        case .partial(let text):
            update(Self.join(base, text))
        case .done(let text):
            update(Self.join(base, text))
            recognizer.stop()
            isListening = false
        case .ended:
            recognizer.stop()
            isListening = false
        }
    }

    static func join(_ base: String, _ dictated: String) -> String {
        guard !dictated.isEmpty else { return base }
        return base.isEmpty ? dictated : base + " " + dictated
    }
}
#endif
