import Foundation

/// Niveaux audio pour l'orbe et pour la détection de parole.
public enum AudioLevel {
    /// RMS sur l'échelle Int16 (0…32767).
    public static func rms(_ samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples {
            let f = Float(s)
            sum += f * f
        }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// Niveau 0…1 en échelle logarithmique : `floorDB` (par défaut −50 dBFS) → 0, 0 dBFS → 1.
    public static func normalized(rms: Float, floorDB: Float = -50) -> Float {
        guard rms > 0, floorDB < 0 else { return 0 }
        let db = 20 * log10(rms / 32768)
        return min(1, max(0, (db - floorDB) / -floorDB))
    }
}

/// Lissage attaque rapide / relâchement lent, pour un orbe qui ne scintille pas.
public struct LevelSmoother: Sendable {
    public var attack: Float
    public var release: Float
    public private(set) var value: Float = 0

    public init(attack: Float = 0.6, release: Float = 0.15) {
        self.attack = attack
        self.release = release
    }

    public mutating func next(_ input: Float) -> Float {
        value += (input - value) * (input > value ? attack : release)
        return value
    }
}
