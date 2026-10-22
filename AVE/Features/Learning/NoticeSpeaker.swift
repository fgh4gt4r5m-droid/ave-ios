#if os(iOS)
import AVFoundation
import UIKit

/// Lecture à voix haute de la notice avec la voix du SYSTÈME (la voix du serveur est aujourd'hui un son de test).
/// Uniquement pour les langues dont iOS fournit une voix (le français) : aucune voix locale n'est simulée.
@MainActor
public final class NoticeSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    public init() {}

    public func isAvailable(languageCode: String) -> Bool {
        AVSpeechSynthesisVoice(language: languageCode) != nil
    }

    public func speak(_ text: String, languageCode: String) {
        guard let voice = AVSpeechSynthesisVoice(language: languageCode) else { return }
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    public func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// VoiceOver lit déjà la feuille : pas de lecture automatique en plus (double voix).
    public static var screenReaderActive: Bool { UIAccessibility.isVoiceOverRunning }
}
#endif
