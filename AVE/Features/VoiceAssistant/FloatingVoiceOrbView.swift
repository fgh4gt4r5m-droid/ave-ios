#if os(iOS)
import SwiftUI

/// Orbe vocal. L'état est porté par le symbole ET le libellé, jamais par la couleur seule.
/// Deux halos suivent le niveau audio ; « Réduire les animations » les fige. Cible tactile d'au moins 44 pt.
public struct FloatingVoiceOrbView: View {
    public let state: OrbState
    /// Niveau 0…1 (micro en écoute, lecture en parole).
    public let level: Float
    /// Diamètre du disque central (le mode vocal plein écran l'agrandit).
    public let diameter: CGFloat
    public var onTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.aveTheme) private var theme

    public init(state: OrbState, level: Float, diameter: CGFloat = 72, onTap: @escaping () -> Void = {}) {
        self.state = state
        self.level = level
        self.diameter = diameter
        self.onTap = onTap
    }

    /// 0…1 si l'orbe doit réagir au son, 0 sinon.
    private var amplitude: CGFloat {
        guard state.followsLevel, !reduceMotion else { return 0 }
        return CGFloat(min(max(level, 0), 1))
    }

    public var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(theme.accent.opacity(0.10))
                    .frame(width: diameter * (1.55 + 0.25 * amplitude), height: diameter * (1.55 + 0.25 * amplitude))
                Circle()
                    .fill(theme.accent.opacity(0.20))
                    .frame(width: diameter * (1.27 + 0.15 * amplitude), height: diameter * (1.27 + 0.15 * amplitude))
                Circle()
                    .fill(theme.accent.opacity(state == .unavailable ? 0.35 : 1))
                    .frame(width: diameter, height: diameter)
                Image(systemName: state.symbolName)
                    .font(.system(size: diameter * 0.32, weight: .semibold))
                    .foregroundStyle(theme.onAccent)
                    .symbolEffect(.pulse, isActive: state == .thinking && !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: diameter * 1.8, height: diameter * 1.8)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: amplitude)
        }
        .buttonStyle(.plain)
        .disabled(!state.isInteractive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Assistant vocal")
        .accessibilityValue(state.label)
        .accessibilityHint(state.hint)
        .accessibilityAddTraits(state.isInteractive ? .isButton : [])
        .sensoryFeedback(.impact(weight: .light), trigger: state == .listening)
        .onChange(of: state) { _, new in
            // Annonce les changements utiles ; la parole de l'assistant s'entend déjà.
            if new == .listening || new == .thinking || new == .unavailable {
                AccessibilityNotification.Announcement(new.label).post()
            }
        }
    }
}
#endif
