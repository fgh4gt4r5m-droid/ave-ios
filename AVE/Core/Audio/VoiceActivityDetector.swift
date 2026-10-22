import Foundation

/// Détecteur de parole à énergie, avec plancher de bruit adaptatif et hystérésis.
///
/// Nécessaire côté client : le serveur du sprint 1 n'a pas de VAD, c'est le client qui signale
/// `end_of_speech`. Une trame = 20 ms. Seuils à calibrer sur le terrain (moto, marché, voiture) ;
/// les valeurs par défaut sont des points de départ, pas des mesures.
public struct VoiceActivityDetector: Sendable {
    public struct Config: Sendable, Equatable {
        /// Trames consécutives au-dessus du seuil avant de déclarer le début de parole (5 = 100 ms).
        public var minSpeechFrames = 5
        /// Trames de silence avant de déclarer la fin (35 = 700 ms).
        public var endSilenceFrames = 35
        /// Seuil RMS minimal (échelle Int16), quel que soit le bruit ambiant.
        public var absoluteThreshold: Float = 600
        public var noiseMultiplier: Float = 3
        /// Pendant que l'assistant parle, le seuil est multiplié : l'écho résiduel ne doit pas couper la réponse.
        public var assistantSpeakingMultiplier: Float = 2
        /// Bornage d'un énoncé (le serveur coupe à 30 s) : 1 500 trames.
        public var maxSpeechFrames = 1_500

        public init() {}
    }

    public enum Event: Sendable, Equatable {
        case speechStarted
        case speechEnded
    }

    public var config: Config
    public private(set) var isInSpeech = false
    public private(set) var noiseFloor: Float = 0
    private var speechRun = 0
    private var silenceRun = 0
    private var speechFrames = 0

    public init(config: Config = Config()) { self.config = config }

    public mutating func reset() {
        isInSpeech = false
        noiseFloor = 0
        speechRun = 0
        silenceRun = 0
        speechFrames = 0
    }

    public func threshold(assistantSpeaking: Bool) -> Float {
        let base = max(config.absoluteThreshold, noiseFloor * config.noiseMultiplier)
        return assistantSpeaking ? base * config.assistantSpeakingMultiplier : base
    }

    /// À appeler une fois par trame de 20 ms avec son RMS.
    public mutating func process(rms: Float, assistantSpeaking: Bool = false) -> Event? {
        let limit = threshold(assistantSpeaking: assistantSpeaking)
        if !isInSpeech {
            if rms > limit {
                speechRun += 1
                if speechRun >= config.minSpeechFrames {
                    isInSpeech = true
                    silenceRun = 0
                    speechFrames = speechRun
                    speechRun = 0
                    return .speechStarted
                }
            } else {
                speechRun = 0
                // Plancher de bruit : descend vite, monte lentement. Jamais appris pendant que
                // l'assistant parle : on y apprendrait l'écho résiduel et le barge-in deviendrait impossible.
                if !assistantSpeaking {
                    noiseFloor += (rms - noiseFloor) * (rms < noiseFloor ? 0.5 : 0.05)
                }
            }
            return nil
        }
        speechFrames += 1
        // Hystérésis : une trame à 60 % du seuil compte encore comme de la parole.
        if rms > limit * 0.6 { silenceRun = 0 } else { silenceRun += 1 }
        if silenceRun >= config.endSilenceFrames || speechFrames >= config.maxSpeechFrames {
            isInSpeech = false
            silenceRun = 0
            speechFrames = 0
            return .speechEnded
        }
        return nil
    }
}

/// Garde les dernières trames pour ne pas perdre le début de la phrase (la détection arrive ~100 ms après).
public struct PreRollBuffer: Sendable {
    public let capacity: Int
    private var frames: [Data] = []

    public init(capacity: Int = 10) { self.capacity = max(0, capacity) }  // 10 trames = 200 ms

    public mutating func push(_ frame: Data) {
        guard capacity > 0 else { return }
        frames.append(frame)
        if frames.count > capacity { frames.removeFirst(frames.count - capacity) }
    }

    /// Renvoie et vide le contenu, dans l'ordre chronologique.
    public mutating func drain() -> [Data] {
        defer { frames.removeAll(keepingCapacity: true) }
        return frames
    }
}
