import Foundation
import Testing
@testable import AVECore

@Suite("Trames binaires")
struct AVEProtocolTests {
    private func bytes(hex: String) -> Data {
        var out = Data()
        var index = hex.startIndex
        while index < hex.endIndex, let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
            if let byte = UInt8(hex[index..<next], radix: 16) { out.append(byte) }
            index = next
        }
        return out
    }

    // Vecteurs OFFICIELS de docs/ios/CLAUDE.md (dépôt serveur), produits par le serveur, repris tels quels.
    @Test("vecteur officiel 1 : micro seq=1, charge 01 00 02 00")
    func official1() throws {
        let expected = bytes(hex: "010000000101000200")
        let frame = AudioFrame(kind: .mic, seq: 1, payload: bytes(hex: "01000200"))
        #expect(frame.encoded() == expected)
        #expect(try AudioFrame.decode(expected) == frame)
    }

    @Test("vecteur officiel 2 : micro seq=258, charge vide")
    func official2() throws {
        let expected = bytes(hex: "0100000102")
        let frame = AudioFrame(kind: .mic, seq: 258, payload: Data())
        #expect(frame.encoded() == expected)
        #expect(try AudioFrame.decode(expected) == frame)
    }

    @Test("vecteur officiel 3 : TTS seq=64, charge ff 7f (échantillon 32767)")
    func official3() throws {
        let expected = bytes(hex: "0200000040ff7f")
        let frame = AudioFrame(kind: .tts, seq: 64, payload: bytes(hex: "ff7f"))
        #expect(frame.encoded() == expected)
        let decoded = try AudioFrame.decode(expected)
        #expect(decoded == frame)
        #expect(PCM16.samples(from: decoded.payload) == [32767])
    }

    // Vecteurs complémentaires, dérivés de ave/protocol.py (pack_audio).
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
