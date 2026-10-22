import Foundation

/// File d'amorçage de la lecture : retient les premières ~100 ms pour absorber la gigue réseau,
/// puis laisse passer les trames au fil de l'eau. Pure et testable.
public struct PlaybackPrimer: Sendable {
    public let primingBytes: Int
    public private(set) var isPrimed = false
    private var held: [Data] = []
    private var heldBytes = 0

    public init(primingMilliseconds: Int = 100, sampleRate: Int = AVEAudio.sampleRate) {
        primingBytes = sampleRate * 2 * primingMilliseconds / 1000
    }

    /// Renvoie les chunks à programmer maintenant.
    public mutating func push(_ pcm: Data) -> [Data] {
        guard !pcm.isEmpty else { return [] }
        if isPrimed { return [pcm] }
        held.append(pcm)
        heldBytes += pcm.count
        guard heldBytes >= primingBytes else { return [] }
        isPrimed = true
        return takeHeld()
    }

    /// Fin de l'énoncé : libère ce qui attend encore (énoncé plus court que l'amorçage) et se réarme.
    public mutating func finish() -> [Data] {
        let out = takeHeld()
        isPrimed = false
        return out
    }

    /// Purge instantanée (barge-in) : on jette tout et on se réarme.
    public mutating func purge() {
        held.removeAll()
        heldBytes = 0
        isPrimed = false
    }

    private mutating func takeHeld() -> [Data] {
        defer { held.removeAll(); heldBytes = 0 }
        return held
    }
}
