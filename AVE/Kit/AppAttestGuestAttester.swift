#if os(iOS)
import AVECore
import CryptoKit
import DeviceCheck
import Foundation

/// Attestation d'appareil (App Attest) pour le mode invité : prouve que la demande vient d'une vraie app sur un vrai iPhone,
/// ce qui limite les comptes invités fabriqués en masse. Indisponible sur simulateur.
public struct AppAttestGuestAttester: GuestAttesting {
    public init() {}

    public func attest(challenge: Data) async throws -> GuestAttestation {
        let service = DCAppAttestService.shared
        guard service.isSupported else { throw AuthError.guestUnsupported }
        let keyID = try await service.generateKey()
        let hash = Data(SHA256.hash(data: challenge))
        let attestation = try await service.attestKey(keyID, clientDataHash: hash)
        return GuestAttestation(keyID: keyID, attestation: attestation)
    }
}
#endif
