import Foundation
import Testing
@testable import AVEKit
@testable import AVECore

@Suite("Audio : découpage et niveaux")
struct AudioFramingTests {
    @Test("le framer produit des trames exactes quelle que soit la taille des blocs")
    func framer() {
        var f = PCMFramer(samplesPerFrame: 320)
        #expect(f.append(Array(repeating: 1, count: 100)).isEmpty)
        let out = f.append(Array(repeating: 2, count: 600))  // 700 au total → 2 trames, 60 restants
        #expect(out.count == 2 && out.allSatisfy { $0.count == 320 })
        #expect(f.bufferedSamples == 60)
        #expect(out[0].prefix(100).allSatisfy { $0 == 1 } && out[0].last == 2)  // ordre conservé
    }

    @Test("constantes du format : 20 ms = 320 échantillons = 640 octets")
    func constants() {
        #expect(AVEAudio.samplesPerFrame == 320)
        #expect(AVEAudio.bytesPerFrame == 640)
    }

    @Test("RMS et niveau normalisé")
    func levels() {
        #expect(AudioLevel.rms([]) == 0)
        #expect(AudioLevel.rms([3, -3, 3, -3]) == 3)
        #expect(AudioLevel.normalized(rms: 0) == 0)
        #expect(AudioLevel.normalized(rms: 32768) == 1)
        let quiet = AudioLevel.normalized(rms: 200), loud = AudioLevel.normalized(rms: 5000)
        #expect(0 < quiet && quiet < loud && loud < 1)
    }

    @Test("lissage : attaque plus rapide que le relâchement")
    func smoother() {
        var s = LevelSmoother()
        let peak = s.next(1)           // montée : 0 → 0,6
        let after = s.next(0)          // descente : 0,6 → 0,51
        #expect(peak > peak - after)   // on monte de 0,6 mais on ne redescend que de 0,09
    }
}

@Suite("Détection de parole")
struct VADTests {
    private func vad() -> VoiceActivityDetector {
        var c = VoiceActivityDetector.Config()
        c.minSpeechFrames = 3
        c.endSilenceFrames = 4
        c.absoluteThreshold = 500
        c.maxSpeechFrames = 50
        return VoiceActivityDetector(config: c)
    }

    private func feed(_ v: inout VoiceActivityDetector, _ rms: Float, _ n: Int, speaking: Bool = false) -> [VoiceActivityDetector.Event] {
        (0..<n).compactMap { _ in v.process(rms: rms, assistantSpeaking: speaking) }
    }

    @Test("début de parole après minSpeechFrames, fin après le silence")
    func startAndEnd() {
        var v = vad()
        #expect(feed(&v, 100, 10).isEmpty)
        #expect(feed(&v, 2000, 2).isEmpty)
        #expect(feed(&v, 2000, 1) == [.speechStarted])
        #expect(feed(&v, 100, 3).isEmpty)
        #expect(feed(&v, 100, 1) == [.speechEnded])
    }

    @Test("un bruit bref ne déclenche rien")
    func shortNoise() {
        var v = vad()
        #expect(feed(&v, 3000, 2).isEmpty)
        #expect(feed(&v, 100, 5).isEmpty)
        #expect(feed(&v, 3000, 2).isEmpty)  // la série a été remise à zéro
    }

    @Test("hystérésis : une voix faible en cours de phrase ne coupe pas")
    func hysteresis() {
        var v = vad()
        _ = feed(&v, 2000, 3)
        #expect(feed(&v, 400, 20).isEmpty)  // 400 > 60 % de 500
        #expect(feed(&v, 100, 4) == [.speechEnded])
    }

    @Test("pendant que l'assistant parle, le seuil double")
    func assistantSpeaking() {
        var v = vad()
        #expect(feed(&v, 800, 10, speaking: true).isEmpty)  // 800 < 1000
        #expect(feed(&v, 1200, 3, speaking: true) == [.speechStarted])
        #expect(v.noiseFloor == 0)  // rien appris pendant que l'assistant parlait
    }

    @Test("le plancher de bruit relève le seuil dans un environnement bruyant")
    func adaptiveFloor() {
        var v = vad()
        _ = feed(&v, 400, 200)  // bruit de fond constant 400 (< seuil absolu 500)
        #expect(v.noiseFloor > 300)
        #expect(v.threshold(assistantSpeaking: false) > 900)  // ≈ 3 × plancher
    }

    @Test("énoncé borné")
    func maxSpeech() {
        var v = vad()
        let events = feed(&v, 2000, 60)
        #expect(events.first == .speechStarted && events.contains(.speechEnded))
    }

    @Test("pré-roll : garde les dernières trames dans l'ordre")
    func preRoll() {
        var p = PreRollBuffer(capacity: 3)
        for i in 1...5 { p.push(Data([UInt8(i)])) }
        #expect(p.drain() == [Data([3]), Data([4]), Data([5])])
        #expect(p.drain().isEmpty)
    }
}

@Suite("Machine d'états du barge-in")
struct BargeInTests {
    private func run(_ inputs: [BargeInStateMachine.Input], from m: BargeInStateMachine = BargeInStateMachine())
        -> (BargeInStateMachine, [BargeInStateMachine.Action]) {
        var m = m
        var actions: [BargeInStateMachine.Action] = []
        for i in inputs { actions += m.handle(i) }
        return (m, actions)
    }

    @Test("tour normal : écoute → réflexion → parole → repos")
    func normalTurn() {
        let (m, a) = run([.userSpeechStarted, .userSpeechEnded, .ttsStarted, .ttsEnded(interrupted: false)])
        #expect(m.phase == .idle)
        #expect(a == [.sendEndOfSpeech])
    }

    @Test("barge-in : purge locale immédiate puis interrupt")
    func bargeIn() {
        let (m, a) = run([.userSpeechStarted, .userSpeechEnded, .ttsStarted, .userSpeechStarted])
        #expect(m.phase == .interrupted)
        #expect(a == [.sendEndOfSpeech, .purgePlayback, .sendInterrupt])
        #expect(!m.acceptsTTSAudio)
    }

    @Test("après barge-in, la confirmation serveur ramène à l'écoute")
    func bargeInConfirmed() {
        let (m, _) = run([.ttsStarted, .userSpeechStarted, .ttsEnded(interrupted: true), .serverInterrupted])
        #expect(m.phase == .listening)
    }

    @Test("barge-in puis fin de parole avant la confirmation : end_of_speech, reliquats ignorés")
    func bargeInThenQuickEnd() {
        let (m, a) = run([.ttsStarted, .userSpeechStarted, .userSpeechEnded, .ttsEnded(interrupted: true), .serverInterrupted])
        #expect(m.phase == .thinking)
        #expect(a == [.purgePlayback, .sendInterrupt, .sendEndOfSpeech])
    }

    @Test("l'audio n'est accepté que pendant la parole")
    func acceptsAudio() {
        var m = BargeInStateMachine()
        #expect(!m.acceptsTTSAudio)
        _ = m.handle(.userSpeechStarted); _ = m.handle(.userSpeechEnded)
        #expect(!m.acceptsTTSAudio)
        _ = m.handle(.ttsStarted)
        #expect(m.acceptsTTSAudio)
    }

    @Test("interruption décidée par le serveur pendant la parole : purge")
    func serverSideBargeIn() {
        let (m, a) = run([.ttsStarted, .ttsEnded(interrupted: true)])
        #expect(m.phase == .idle && a == [.purgePlayback])
        let (m2, a2) = run([.ttsStarted, .serverInterrupted])
        #expect(m2.phase == .idle && a2 == [.purgePlayback])
    }

    @Test("l'utilisateur reprend la parole pendant la réflexion")
    func speakWhileThinking() {
        let (m, a) = run([.userSpeechStarted, .userSpeechEnded, .userSpeechStarted])
        #expect(m.phase == .listening && a == [.sendEndOfSpeech])
    }

    @Test("reliquat tardif en réflexion ignoré, ttsStarted du nouveau tour accepté")
    func staleIgnored() {
        let (m, _) = run([.userSpeechStarted, .userSpeechEnded, .ttsEnded(interrupted: true), .serverInterrupted])
        #expect(m.phase == .thinking)
        var m2 = m
        _ = m2.handle(.ttsStarted)
        #expect(m2.phase == .speaking)
    }

    @Test("turn_error ou délai : retour au repos ; session perdue : purge si on parlait")
    func failures() {
        #expect(run([.userSpeechStarted, .userSpeechEnded, .turnFailed]).0.phase == .idle)
        let (m, a) = run([.ttsStarted, .sessionLost])
        #expect(m.phase == .idle && a == [.purgePlayback])
        #expect(run([.userSpeechStarted, .sessionLost]).0.phase == .idle)
    }

    @Test("ttsStarted pendant l'écoute est ignoré (réponse périmée)")
    func ttsWhileListening() {
        let (m, _) = run([.userSpeechStarted, .ttsStarted])
        #expect(m.phase == .listening)
        #expect(!m.acceptsTTSAudio)
    }
}

@Suite("Amorçage de lecture")
struct PlaybackPrimerTests {
    private let chunk = Data(count: 640)  // 20 ms

    @Test("retient 100 ms puis laisse passer")
    func priming() {
        var p = PlaybackPrimer(primingMilliseconds: 100)
        for _ in 0..<4 { #expect(p.push(chunk).isEmpty) }
        #expect(p.push(chunk).count == 5 && p.isPrimed)
        #expect(p.push(chunk).count == 1)
    }

    @Test("énoncé plus court que l'amorçage : libéré par finish, puis réarmé")
    func shortUtterance() {
        var p = PlaybackPrimer(primingMilliseconds: 100)
        _ = p.push(chunk)
        #expect(p.finish().count == 1)
        #expect(!p.isPrimed)
        #expect(p.push(chunk).isEmpty)
    }

    @Test("purge : tout est jeté et la file se réarme")
    func purge() {
        var p = PlaybackPrimer(primingMilliseconds: 100)
        for _ in 0..<5 { _ = p.push(chunk) }
        p.purge()
        #expect(!p.isPrimed && p.finish().isEmpty)
    }

    @Test("chunk vide ignoré")
    func empty() {
        var p = PlaybackPrimer()
        #expect(p.push(Data()).isEmpty)
    }
}
