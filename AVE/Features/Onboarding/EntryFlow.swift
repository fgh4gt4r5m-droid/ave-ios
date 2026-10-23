import AVECore
import Foundation

/// Après le numéro et le code (ou Apple, ou l'essai sans compte) : le nom complet, puis l'âge et les conditions
/// (maquette « Entrée dans AVE » validée par le propriétaire le 2026-10-23). Pur, testé.
public enum EntryFlow {
    public enum Step: Sendable, Equatable {
        /// « Comment vous appelez-vous ? » ; `suggestion` : le nom donné par Apple, s'il y en a un.
        case name(suggestion: String?)
        /// « Avant de commencer » : 18 ans ou plus, conditions d'utilisation et politique de confidentialité.
        case terms
        case done
    }

    /// Ce qu'il reste à demander. Le profil du service de comptes fait foi ; à défaut (hors ligne), ce que l'iPhone a déjà
    /// noté. Un essai sans compte n'a pas d'écran de nom (il n'a pas de compte à nommer) mais accepte les conditions.
    public static func next(kind: AccountKind, profile: AccountProfile?, localFullName: String, localTermsVersion: String?,
                            suggestedName: String? = nil) -> Step {
        let name = (profile?.fullName ?? localFullName).trimmingCharacters(in: .whitespacesAndNewlines)
        if kind != .guest, name.isEmpty { return .name(suggestion: suggestedName) }
        let accepted = (profile.map { $0.termsVersion == Terms.currentVersion && $0.adultConfirmed } ?? false)
            || localTermsVersion == Terms.currentVersion
        return accepted ? .done : .terms
    }

    /// « Fatou Camara » → « Fatou » : la salutation de l'accueil (« Bonjour, Fatou »).
    public static func firstName(of fullName: String) -> String {
        fullName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }

    /// Nom saisi, nettoyé comme le fait le service (espaces superflus retirés) ; `nil` s'il est trop court ou trop long.
    public static func cleanedName(_ input: String) -> String? {
        let name = input.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard name.count >= 2, name.count <= 80 else { return nil }
        return name
    }

    /// Nom complet d'Apple (`PersonNameComponents`), donné seulement à la première connexion.
    public static func appleName(given: String?, family: String?) -> String? {
        let parts = [given, family].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
