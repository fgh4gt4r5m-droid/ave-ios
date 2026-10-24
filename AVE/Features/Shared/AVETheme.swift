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

    /// Charte de l'app AVE, aux standards des assistants d'iOS (ChatGPT, Claude, Gemini ; décision du 2026-10-23) :
    /// fonds et bulles du SYSTÈME, en apparence claire comme sombre ; la marque ne colore que l'accent (envoi, mode
    /// vocal, orbe) et les avertissements. Contrastes vérifiés par les tests (`ScreenLogicTests.contrasts`).
    public static let ave = AVETheme(
        accent: .adaptive(light: AVEPalette.blueOnLight, dark: AVEPalette.blue),
        onAccent: .adaptive(light: AVEPalette.white, dark: AVEPalette.navy),
        background: nil,
        userBubble: Color(.secondarySystemBackground), userBubbleText: .primary,
        assistantBubble: Color(.secondarySystemBackground), assistantBubbleText: .primary,
        warning: .adaptive(light: AVEPalette.amberOnLight, dark: AVEPalette.amber))
}

extension Color {
    public init(_ c: AVEColor) {
        self.init(red: Double(c.red) / 255, green: Double(c.green) / 255, blue: Double(c.blue) / 255)
    }

    /// Couleur qui suit l'apparence du système (claire / sombre).
    public static func adaptive(light: AVEColor, dark: AVEColor) -> Color {
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(c.red) / 255, green: CGFloat(c.green) / 255, blue: CGFloat(c.blue) / 255, alpha: 1)
        })
    }
}

private struct AVEThemeKey: EnvironmentKey {
    static let defaultValue = AVETheme.standard
}

extension EnvironmentValues {
    /// Vibrations autorisées (réglage « Vibrations » de l'app, ou choix de l'app hôte).
    @Entry public var aveHaptics: Bool = true

    public var aveTheme: AVETheme {
        get { self[AVEThemeKey.self] }
        set { self[AVEThemeKey.self] = newValue }
    }
}
#endif
