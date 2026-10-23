import Foundation

/// Indicatif proposé dans l'écran « Votre numéro » (maquette d'entrée validée le 2026-10-23) : on choisit le pays au
/// lieu de taper « +224 ». Liste courte et ordonnée pour le public d'AVE (Afrique de l'Ouest et centrale d'abord, puis
/// les diasporas les plus nombreuses) ; un numéro tapé avec « + » reste accepté pour tout autre pays.
public struct PhoneCountry: Sendable, Equatable, Identifiable {
    /// Code ISO 3166 à deux lettres (sert au drapeau).
    public let region: String
    public let name: String
    /// Indicatif sans « + ».
    public let dialCode: String

    public var id: String { region }

    /// Drapeau construit à partir du code ISO (lettres régionales Unicode), sans image à embarquer.
    public var flag: String {
        region.uppercased().unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }
            .map(String.init).joined()
    }

    public static let all: [PhoneCountry] = [
        PhoneCountry(region: "GN", name: "Guinée", dialCode: "224"),
        PhoneCountry(region: "SN", name: "Sénégal", dialCode: "221"),
        PhoneCountry(region: "CI", name: "Côte d'Ivoire", dialCode: "225"),
        PhoneCountry(region: "ML", name: "Mali", dialCode: "223"),
        PhoneCountry(region: "BF", name: "Burkina Faso", dialCode: "226"),
        PhoneCountry(region: "NE", name: "Niger", dialCode: "227"),
        PhoneCountry(region: "TG", name: "Togo", dialCode: "228"),
        PhoneCountry(region: "BJ", name: "Bénin", dialCode: "229"),
        PhoneCountry(region: "SL", name: "Sierra Leone", dialCode: "232"),
        PhoneCountry(region: "LR", name: "Liberia", dialCode: "231"),
        PhoneCountry(region: "GW", name: "Guinée-Bissau", dialCode: "245"),
        PhoneCountry(region: "GM", name: "Gambie", dialCode: "220"),
        PhoneCountry(region: "MR", name: "Mauritanie", dialCode: "222"),
        PhoneCountry(region: "CM", name: "Cameroun", dialCode: "237"),
        PhoneCountry(region: "GA", name: "Gabon", dialCode: "241"),
        PhoneCountry(region: "CG", name: "Congo", dialCode: "242"),
        PhoneCountry(region: "CD", name: "RD Congo", dialCode: "243"),
        PhoneCountry(region: "MA", name: "Maroc", dialCode: "212"),
        PhoneCountry(region: "FR", name: "France", dialCode: "33"),
        PhoneCountry(region: "BE", name: "Belgique", dialCode: "32"),
        PhoneCountry(region: "US", name: "États-Unis / Canada", dialCode: "1"),
    ]

    /// Pays de l'indicatif donné (le premier de la liste pour un indicatif partagé).
    public static func forDialCode(_ code: String?) -> PhoneCountry? {
        guard let code else { return nil }
        return all.first { $0.dialCode == code }
    }
}
