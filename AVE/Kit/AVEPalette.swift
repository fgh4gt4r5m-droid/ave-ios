import Foundation

/// Palette de la marque AVE, relevée sur le logo retenu (valeurs approximatives, à confirmer avec le designer).
/// Pure (sans SwiftUI) : partagée par l'app, la Live Activity et les tests de contraste.
public struct AVEColor: Sendable, Equatable {
    public let red: UInt8, green: UInt8, blue: UInt8

    public init(hex: UInt32) {
        red = UInt8((hex >> 16) & 0xFF)
        green = UInt8((hex >> 8) & 0xFF)
        blue = UInt8(hex & 0xFF)
    }

    /// Luminance relative WCAG 2.
    public var luminance: Double {
        func lin(_ v: UInt8) -> Double {
            let c = Double(v) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }

    /// Rapport de contraste WCAG (1…21). Texte courant : ≥ 4,5 ; grand texte et icônes : ≥ 3.
    public func contrast(with other: AVEColor) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

public enum AVEPalette {
    /// Fond de la marque (relevé : #010A29).
    public static let navy = AVEColor(hex: 0x010A29)
    /// Bleu vif des barres du « E » (relevé : #5EA0FD) : couleur d'accent interactive.
    public static let blue = AVEColor(hex: 0x5EA0FD)
    /// Ambre du point du « A » (relevé : #FEBD3F) : mise en avant, avertissements.
    public static let amber = AVEColor(hex: 0xFEBD3F)
    /// Violet du dégradé (relevé : #813EF3) : réservé aux décors et à l'orbe, jamais au texte (3,6:1 sur le fond).
    public static let violet = AVEColor(hex: 0x813EF3)
    /// Surface des bulles et cartes : bleu nuit éclairci (DÉRIVÉ, non relevé).
    public static let surface = AVEColor(hex: 0x101C4D)
    public static let white = AVEColor(hex: 0xFFFFFF)
}
