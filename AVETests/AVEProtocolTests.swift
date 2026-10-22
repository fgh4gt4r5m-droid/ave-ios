import Foundation
import Testing
@testable import AVECore

@Suite("Trames binaires")
struct AVEProtocolTests {
    // Vecteurs DÉRIVÉS de ave/protocol.py (pack_audio) : CLAUDE.md est absent du dépôt, les
    // vecteurs officiels n'ont donc pas pu être repris. À comparer à CLAUDE.md dès qu'il est fourni.
    @Test("vecteur 1 : micro seq=1, échantillon 1")
    func vector1() throws {
        let bytes: [UInt8] = [0x01, 0x00, 0x00, 0x00, 0x01, 0x01, 0x00]
        let frame = AudioFrame(kind: .mic, seq: 1, payload: PCM16.data(from: [1]))
        #expect(Array(frame.encoded()) == bytes)
        #expect(try AudioFrame.decode(Data(bytes)) == frame)
    }

    @Test("vecteur 2 : seq big-endian, PCM little-endian signé")
    func vector2() throws {
        let bytes: [UInt8] = [0x01, 0x01, 0x02, 0x03, 0x04, 0x34, 0x12, 0xFE, 0xFF]
        let frame = AudioFrame(kind: .mic, seq: 0x0102_0304, payload: PCM16.data(from: [0x1234, -2]))
        #expect(Array(frame.encoded()) == bytes)
        let decoded = try AudioFrame.decode(Data(bytes))
        #expect(decoded.seq == 0x0102_0304)
        #expect(PCM16.samples(from: decoded.payload) == [0x1234, -2])
    }

    @Test("vecteur 3 : TTS, seq maximal, charge vide")
    func vector3() throws {
        let bytes: [UInt8] = [0x02, 0xFF, 0xFF, 0xFF, 0xFF]
        let frame = AudioFrame(kind: .tts, seq: .max, payload: Data())
        #expect(Array(frame.encoded()) == bytes)
        #expect(try AudioFrame.decode(Data(bytes)) == frame)
    }

    @Test("trame trop courte")
    func tooShort() {
        #expect(throws: AVEProtocolError.frameTooShort) { try AudioFrame.decode(Data([0x01, 0, 0, 0])) }
        #expect(throws: AVEProtocolError.frameTooShort) { try AudioFrame.decode(Data()) }
    }

    @Test("kind inconnu")
    func unknownKind() {
        #expect(throws: AVEProtocolError.unexpectedKind(0x09)) {
            try AudioFrame.decode(Data([0x09, 0, 0, 0, 1]))
        }
    }

    @Test("décodage d'une tranche de Data (startIndex ≠ 0)")
    func slice() throws {
        let whole = Data([0xAA, 0xBB, 0x02, 0x00, 0x00, 0x00, 0x07, 0x05, 0x00])
        let slice = whole[2...]
        let f = try AudioFrame.decode(slice)
        #expect(f.kind == .tts && f.seq == 7)
        #expect(PCM16.samples(from: f.payload) == [5])
    }

    @Test("PCM16 aller-retour, extrêmes inclus")
    func pcmRoundTrip() {
        let s: [Int16] = [0, 1, -1, .max, .min, 12345]
        #expect(PCM16.samples(from: PCM16.data(from: s)) == s)
    }
}
