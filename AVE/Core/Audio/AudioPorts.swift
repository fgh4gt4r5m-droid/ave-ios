import Foundation

/// Trame micro de 20 ms, prête pour le protocole (PCM16 mono 16 kHz).
public struct MicFrame: Sendable, Equatable {
    public let pcm: Data
    public let rms: Float

    public init(pcm: Data, rms: Float) {
        self.pcm = pcm
        self.rms = rms
    }
}

public enum AudioRoute: Sendable, Equatable {
    case builtInSpeaker, receiver, headphones, bluetooth, other
}

public enum AudioRouteChangeReason: Sendable, Equatable {
    case newDeviceAvailable, oldDeviceUnavailable, categoryChange, override, other
}

public enum AudioSessionEvent: Sendable, Equatable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(AudioRoute, reason: AudioRouteChangeReason)
    case mediaServicesReset
}

/// Les ports ci-dessous isolent le matériel : le coordinateur de session se teste avec des faux.
public protocol MicSource: Sendable {
    var frames: AsyncStream<MicFrame> { get }
    func start()
    func stop()
}

public protocol SpeechPlayer: Sendable {
    var levels: AsyncStream<Float> { get }
    /// Vrai quand plus rien n'est programmé ni en cours de lecture.
    var isDrained: Bool { get }
    func enqueue(_ pcm: Data)
    func endOfUtterance()
    func purge()
}

public protocol AudioLifecycle: Sendable {
    var events: AsyncStream<AudioSessionEvent> { get }
    func requestMicrophonePermission() async -> Bool
    func activate() throws
    func deactivate()
}

public struct AudioDevices: Sendable {
    public let mic: any MicSource
    public let player: any SpeechPlayer
    public let lifecycle: any AudioLifecycle

    public init(mic: any MicSource, player: any SpeechPlayer, lifecycle: any AudioLifecycle) {
        self.mic = mic
        self.player = player
        self.lifecycle = lifecycle
    }
}
