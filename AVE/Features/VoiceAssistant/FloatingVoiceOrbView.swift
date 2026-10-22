#if os(iOS)
import SwiftUI

/// Orbe vocal. L'état est porté par le symbole ET le libellé, jamais par la couleur seule.
/// Réduction des animations respectée ; cible tactile d'au moins 44 pt.
public struct FloatingVoiceOrbView: View {
    public let state: OrbState
    /// Niveau 0…1 (micro en écoute, lecture en parole).
    public let level: Float
    public var onTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.aveTheme) private var theme

    public init(state: OrbState, level: Float, onTap: @escaping () -> Void = {}) {
        self.state = state
        self.level = level
        self.onTap = onTap
    }

    private var scale: CGFloat {
        guard state.followsLevel, !reduceMotion else { return 1 }
        return 1 + CGFloat(min(max(level, 0), 1)) * 0.25
    }

    public var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(theme.accent.opacity(state == .unavailable ? 0.25 : 0.9))
                    .scaleEffect(scale)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: scale)
                Image(systemName: state.symbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(theme.onAccent)
                    .symbolEffect(.pulse, isActive: state == .thinking && !reduceMotion)
            }
            .frame(width: 72, height: 72)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!state.isInteractive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Assistant vocal")
        .accessibilityValue(state.label)
        .accessibilityHint(state.hint)
        .accessibilityAddTraits(state.isInteractive ? .isButton : [])
        .onChange(of: state) { _, new in
            // Annonce les changements utiles ; la parole de l'assistant s'entend déjà.
            if new == .listening || new == .thinking || new == .unavailable {
                AccessibilityNotification.Announcement(new.label).post()
            }
        }
    }
}
#endif
