import Foundation

/// Intensité de la lumière douce, pure et testée (les vues sont réservées à iOS) : jamais de flash, un plafond bas.
public enum GlowLevel {
    /// Lumière du mode vocal : 22 % au silence, 80 % au plus ; paliers de 5 % (la transition lisse le reste, sans
    /// redessiner à chaque trame audio) ; « Réduire les animations » : fixe à 35 %.
    public static func edge(level: Float, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0.35 }
        return step(min(0.22 + 0.55 * clamped(level), 0.8))
    }

    /// Halo autour de la saisie : plus discret (18 % à 60 %) ; fixe à 30 % avec « Réduire les animations ».
    public static func halo(level: Float, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0.3 }
        return step(min(0.18 + 0.42 * clamped(level), 0.6))
    }

    private static func clamped(_ level: Float) -> Double { Double(min(max(level, 0), 1)) }
    private static func step(_ value: Double) -> Double { (value * 20).rounded() / 20 }
}

#if os(iOS)
import SwiftUI

/// Lumière douce sur le pourtour de l'écran, comme la lisière de Siri (maquette « Lumière et suggestions AVE », validée
/// le 2026-10-23) : froide quand la personne parle, chaude quand AVE parle. Un calque à part, derrière tout : le symbole
/// et ses animations ne changent pas.
/// - Jamais de flash : l'intensité suit le niveau du son (déjà lissé), par paliers, avec une transition d'une demi-seconde,
///   et reste plafonnée bas ; les couleurs tournent lentement (8 s par tour).
/// - « Réduire les animations » : lueur fixe et légère. Contraste élevé : pas de lueur.
/// - L'état reste écrit à l'écran et dit par VoiceOver : la couleur seule ne porte aucune information.
struct AmbientGlow: View {
    enum Mood: Equatable {
        case listening, speaking
    }

    let mood: Mood?
    /// Niveau du son, 0…1 (micro quand la personne parle, voix d'AVE quand AVE parle).
    let level: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if let mood, contrast != .increased {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                let turn = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8
                RoundedRectangle(cornerRadius: 56, style: .continuous)
                    .strokeBorder(AngularGradient(colors: Self.colors(mood), center: .center, angle: .degrees(turn * 360)),
                                  lineWidth: 34)
                    .blur(radius: 28)
            }
            .opacity(GlowLevel.edge(level: level, reduceMotion: reduceMotion))
            .animation(.easeOut(duration: 0.5), value: GlowLevel.edge(level: level, reduceMotion: reduceMotion))
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }

    /// Les couleurs du dégradé du symbole : bleus et cyan pour l'écoute, violets, magenta et la touche ambre pour la parole.
    static func colors(_ mood: Mood) -> [Color] {
        switch mood {
        case .listening:
            return [rgb(0x3B5BFF), rgb(0x14B4FF), rgb(0x00E5FF), rgb(0x6A7CFF), rgb(0x3B5BFF)]
        case .speaking:
            return [rgb(0xE11DF5), rgb(0x7C3AED), rgb(0xFFB020), rgb(0xC026F5), rgb(0x8B3DF5), rgb(0xE11DF5)]
        }
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Halo très léger autour de la barre de saisie quand AVE lit une réponse à voix haute dans la conversation écrite
/// (écran 4 validé). Le reste de l'écran ne bouge pas.
struct ReadingHalo: View {
    let active: Bool
    let level: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if active, contrast != .increased {
            let opacity = GlowLevel.halo(level: level, reduceMotion: reduceMotion)
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(AngularGradient(colors: AmbientGlow.colors(.speaking), center: .center), lineWidth: 6)
                .blur(radius: 8)
                .padding(-5)
                .opacity(opacity)
                .animation(.easeOut(duration: 0.5), value: opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }
}
#endif
