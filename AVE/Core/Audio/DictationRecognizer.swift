#if os(iOS)
import AVFoundation
import Speech

/// Dictée de la barre de saisie avec la reconnaissance vocale d'Apple, SUR L'IPHONE seulement (décision du propriétaire,
/// 2026-10-23) : le son ne quitte pas l'appareil. Sans reconnaissance locale du français, la dictée n'est pas proposée
/// (jamais de repli sur les serveurs d'Apple). Indépendante de la session AVE : rien n'est envoyé au moteur.
///
/// Comme `MicCapture`, le tap est posé hors de l'acteur principal (classe non isolée) : sous Swift 6, un bloc créé sur
/// l'acteur principal et appelé sur le fil audio planterait.
public final class DictationRecognizer: @unchecked Sendable {
    public enum Event: Sendable, Equatable {
        /// Texte reconnu jusqu'ici (il s'affine au fil de la parole).
        case partial(String)
        /// Texte définitif, après `finish()`.
        case done(String)
        /// Fin sans texte définitif (silence, interruption) : on garde ce qui est déjà écrit.
        case ended
    }

    public struct Unavailable: Error {}

    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))

    public init() {}

    /// Autorisation de la reconnaissance vocale (demandée au premier usage).
    public static func authorize() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    /// `onEvent` est appelé sur une file quelconque.
    public func start(onEvent: @escaping @Sendable (Event) -> Void) throws {
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw Unavailable() }
        stop()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Le bloc du tap peut être déclaré `@Sendable` par le SDK : la requête passe dans une boîte (Apple documente
        // `append` comme utilisable depuis le fil audio).
        let box = RequestBox(request)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            box.request.append(buffer)  // rien d'autre sur le fil audio
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            throw Unavailable()
        }
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                onEvent(result.isFinal ? .done(text) : .partial(text))
            } else if error != nil {
                onEvent(.ended)
            }
        }
        lock.withLock {
            self.engine = engine
            self.request = request
            self.task = task
        }
    }

    /// La personne a fini : on coupe le micro et on laisse la reconnaissance rendre le texte définitif.
    public func finish() {
        lock.withLock {
            engine?.stop()
            engine?.inputNode.removeTap(onBus: 0)
            engine = nil
            request?.endAudio()
        }
    }

    /// Abandon immédiat (envoi, mode vocal, sortie de l'écran).
    public func stop() {
        lock.withLock {
            engine?.stop()
            engine?.inputNode.removeTap(onBus: 0)
            engine = nil
            task?.cancel()
            task = nil
            request = nil
        }
    }
}

private final class RequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
}
#endif
