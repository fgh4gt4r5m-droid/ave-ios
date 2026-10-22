/// Format audio du protocole AVE : PCM16 mono 16 kHz, trames de 20 ms.
public enum AVEAudio {
    public static let sampleRate = 16_000
    public static let frameMilliseconds = 20
    public static let samplesPerFrame = sampleRate * frameMilliseconds / 1000  // 320
    public static let bytesPerFrame = samplesPerFrame * 2                      // 640
}
