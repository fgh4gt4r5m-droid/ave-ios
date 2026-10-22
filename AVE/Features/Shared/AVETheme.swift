#if os(iOS)
import SwiftUI

/// Charte graphique remplaçable : WoYo et TaGa injectent la leur via `.environment(\.aveTheme, …)`.
public struct AVETheme: Sendable {
    public var accent: Color
    public var userBubble: Color
    public var userBubbleText: Color
    public var assistantBubble: Color
    public var assistantBubbleText: Color
    public var warning: Color
    public var cornerRadius: CGFloat

    public init(accent: Color = .accentColor, userBubble: Color = .accentColor, userBubbleText: Color = .white,
                assistantBubble: Color = Color(.secondarySystemBackground), assistantBubbleText: Color = .primary,
                warning: Color = .orange, cornerRadius: CGFloat = 18) {
        self.accent = accent
        self.userBubble = userBubble
        self.userBubbleText = userBubbleText
        self.assistantBubble = assistantBubble
        self.assistantBubbleText = assistantBubbleText
        self.warning = warning
        self.cornerRadius = cornerRadius
    }

    public static let standard = AVETheme()
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
