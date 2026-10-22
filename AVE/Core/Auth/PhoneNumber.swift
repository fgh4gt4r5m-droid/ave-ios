/// Numéro au format international (E.164). Validation de FORME seulement : l'existence du numéro est vérifiée par le code reçu.
public struct PhoneNumber: Sendable, Equatable {
    public let e164: String  // « + » puis 8 à 15 chiffres

    /// `defaultCountryCode` (sans « + », ex. « 224 ») complète un numéro saisi sans indicatif ; un « 0 » de tête (préfixe local) est alors retiré.
    public init?(_ raw: String, defaultCountryCode: String? = nil) {
        var s = raw.filter { !" -.()\u{00A0}".contains($0) }
        if s.hasPrefix("00") { s = "+" + s.dropFirst(2) }
        if !s.hasPrefix("+") {
            guard let code = defaultCountryCode, code.allSatisfy(\.isASCIINumber) else { return nil }
            if s.hasPrefix("0") { s.removeFirst() }
            s = "+" + code + s
        }
        let digits = s.dropFirst()
        guard (8...15).contains(digits.count), digits.allSatisfy(\.isASCIINumber), digits.first != "0" else { return nil }
        e164 = s
    }

    /// Affichage sans exposer le numéro entier (« +224 •••• •• 67 »).
    public var masked: String {
        let tail = e164.suffix(2)
        return String(e164.prefix(4)) + " •••• •• " + tail
    }
}

private extension Character {
    var isASCIINumber: Bool { ("0"..."9").contains(self) }
}
