/// Découpe un flux d'échantillons de taille quelconque en trames exactes (20 ms = 320 échantillons).
public struct PCMFramer: Sendable {
    public let samplesPerFrame: Int
    private var pending: [Int16] = []

    public init(samplesPerFrame: Int = AVEAudio.samplesPerFrame) {
        self.samplesPerFrame = max(1, samplesPerFrame)
    }

    public var bufferedSamples: Int { pending.count }

    public mutating func append(_ samples: [Int16]) -> [[Int16]] {
        pending.append(contentsOf: samples)
        var frames: [[Int16]] = []
        var start = 0
        while pending.count - start >= samplesPerFrame {
            frames.append(Array(pending[start..<(start + samplesPerFrame)]))
            start += samplesPerFrame
        }
        if start > 0 { pending.removeFirst(start) }
        return frames
    }

    public mutating func reset() { pending.removeAll(keepingCapacity: true) }
}
