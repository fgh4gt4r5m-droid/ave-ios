#if os(iOS)
import SwiftUI

/// Charte graphique remplaçable : WoYo et TaGa injectent la leur via `.environment(\.aveTheme, …)`.
public struct AVETheme: Sendable {
    public var accent: Color
    /// Couleur des icônes et du texte posés SUR l'accent (le blanc sur le bleu vif ne passe pas : 2,7:1).
    public var onAccent: Color
    public var background: Color?
    public var userBubble: Color
    public var userBubbleText: Color
    public var assistantBubble: Color
    public var assistantBubbleText: Color
    public var warning: Color
    public var cornerRadius: CGFloat

    public init(accent: Color = .accentColor, onAccent: Color = .white, background: Color? = nil,
                userBubble: Color = .accentColor, userBubbleText: Color = .white,
                assistantBubble: Color = Color(.secondarySystemBackground), assistantBubbleText: Color = .primary,
                warning: Color = .orange, cornerRadius: CGFloat = 18) {
        self.accent = accent
        self.onAccent = onAccent
        self.background = background
        self.userBubble = userBubble
        self.userBubbleText = userBubbleText
        self.assistantBubble = assistantBubble
        self.assistantBubbleText = assistantBubbleText
        self.warning = warning
        self.cornerRadius = cornerRadius
    }

    /// Thème neutre (couleurs système) : défaut pour les apps hôtes, qui injectent leur propre charte.
    public static let standard = AVETheme()

    /// Charte de l'app AVE (logo retenu). Contrastes vérifiés par les tests (`AVEPaletteTests`).
    public static let ave = AVETheme(
        accent: Color(AVEPalette.blue), onAccent: Color(AVEPalette.navy), background: Color(AVEPalette.navy),
        userBubble: Color(AVEPalette.blue), userBubbleText: Color(AVEPalette.navy),
        assistantBubble: Color(AVEPalette.surface), assistantBubbleText: Color(AVEPalette.white),
        warning: Color(AVEPalette.amber))
}

extension Color {
    public init(_ c: AVEColor) {
        self.init(red: Double(c.red) / 255, green: Double(c.green) / 255, blue: Double(c.blue) / 255)
    }
}

private struct AVEThemeKey: EnvironmentKey {
    static let defaultValue = AVETheme.standard
}

extension EnvironmentValues {
    public var aveTheme: AVETheme {
        get { self[AVEThemeKey.self] }
        set { self[AVEThemeKey.self] = newValue }
    }
}
#endif
