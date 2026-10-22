import Foundation

/// Trame audio binaire : `kind u8` · `seq u32 big-endian` · PCM16 mono little-endian.
public struct AudioFrame: Sendable, Equatable {
    public enum Kind: UInt8, Sendable {
        case mic = 0x01  // client → serveur
        case tts = 0x02  // serveur → client
    }

    public static let headerSize = 5

    public let kind: Kind
    public let seq: UInt32
    public let payload: Data

    public init(kind: Kind, seq: UInt32, payload: Data) {
        self.kind = kind
        self.seq = seq
        self.payload = payload
    }

    public func encoded() -> Data {
        var out = Data(capacity: Self.headerSize + payload.count)
        out.append(kind.rawValue)
        out.append(UInt8(truncatingIfNeeded: seq >> 24))
        out.append(UInt8(truncatingIfNeeded: seq >> 16))
        out.append(UInt8(truncatingIfNeeded: seq >> 8))
        out.append(UInt8(truncatingIfNeeded: seq))
        out.append(payload)
        return out
    }

    public static func decode(_ data: Data) throws -> AudioFrame {
        guard data.count >= headerSize else { throw AVEProtocolError.frameTooShort }
        // `Data` peut être une tranche (startIndex ≠ 0) : on indexe depuis startIndex.
        let base = data.startIndex
        guard let kind = Kind(rawValue: data[base]) else {
            throw AVEProtocolError.unexpectedKind(data[base])
        }
        var seq: UInt32 = 0
        for i in 1...4 { seq = (seq << 8) | UInt32(data[base + i]) }
        return AudioFrame(kind: kind, seq: seq, payload: Data(data[(base + headerSize)...]))
    }
}

/// Conversions PCM16 little-endian ↔ échantillons, indépendantes de l'endianness de la machine.
public enum PCM16 {
    public static func data(from samples: [Int16]) -> Data {
        var out = Data(capacity: samples.count * 2)
        for s in samples {
            let u = UInt16(bitPattern: s)
            out.append(UInt8(truncatingIfNeeded: u))
            out.append(UInt8(truncatingIfNeeded: u >> 8))
        }
        return out
    }

    public static func samples(from data: Data) -> [Int16] {
        let base = data.startIndex
        let n = data.count / 2
        return (0..<n).map { i in
            let lo = UInt16(data[base + 2 * i])
            let hi = UInt16(data[base + 2 * i + 1])
            return Int16(bitPattern: lo | (hi << 8))
        }
    }
}
