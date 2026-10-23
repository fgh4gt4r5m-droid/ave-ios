#if os(iOS)
import AVECore
import SwiftUI

/// Premier lancement (proposition 2) : une promesse claire, puis le choix de la langue AVANT la connexion. Grandes
/// tuiles avec le nom local et le statut RÉEL (liste de repli : le serveur n'est pas encore joint à ce moment-là).
/// Une langue « Bientôt » reste choisissable, et l'app le dit ensuite dans la conversation.
public struct OnboardingView: View {
    let onFinish: (AVELanguage) -> Void
    @State private var page = 0
    @State private var selection: AVELanguage = .french
    @Environment(\.aveTheme) private var theme

    public init(onFinish: @escaping (AVELanguage) -> Void) {
        self.onFinish = onFinish
    }

    private var options: [LanguageOption] {
        LanguageCatalog.builtIn.filter { $0.language != .auto }
    }

    public var body: some View {
        VStack(spacing: 18) {
            if page == 0 { welcome } else { languages }
            HStack(spacing: 6) {
                ForEach(0..<2) { index in
                    Capsule()
                        .fill(index == page ? Color.primary : Color.secondary.opacity(0.35))
                        .frame(width: index == page ? 20 : 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            Button {
                if page == 0 { withAnimation { page = 1 } } else { onFinish(selection) }
            } label: {
                Text(page == 0 ? "Commencer" : "Continuer")
                    .font(.headline)
                    .foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(theme.accent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background((theme.background ?? Color(.systemBackground)).ignoresSafeArea())
    }

    private var welcome: some View {
        VStack(spacing: 26) {
            Spacer()
            AVEMark().frame(width: 132, height: 132)
            VStack(spacing: 12) {
                Text("Votre assistant, dans votre langue.")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Parlez ou écrivez. AVE vous répond à voix haute et par écrit.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .transition(.opacity)
    }

    private var languages: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Dans quelle langue voulez-vous parler ?")
                    .font(.largeTitle.weight(.bold))
                    .padding(.top, 40)
                Text("Vous pourrez la changer à tout moment.").foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(options) { option in
                        tile(option)
                    }
                }
                .padding(.top, 14)
            }
        }
        .transition(.opacity)
    }

    private func tile(_ option: LanguageOption) -> some View {
        let selected = option.language == selection
        return Button { selection = option.language } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(option.name).font(.headline)
                if let native = option.nativeName { Text(native).font(.footnote).foregroundStyle(.secondary) }
                Label(option.isAvailable ? "Disponible" : "Bientôt",
                      systemImage: option.isAvailable ? "checkmark.circle.fill" : "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(option.isAvailable ? Color.green : theme.warning)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .padding(14)
            .background(theme.assistantBubble, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? theme.accent : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(option.isAvailable ? "" : "Pas encore disponible : l'assistant ne pourra pas répondre.")
    }
}

/// Marque provisoire : sept barres de son, la centrale en ambre (comme l'icône provisoire de l'app).
struct AVEMark: View {
    private let heights: [CGFloat] = [0.16, 0.30, 0.46, 0.62, 0.46, 0.30, 0.16]

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.23).fill(Color(AVEPalette.navy))
                HStack(spacing: size * 0.052) {
                    ForEach(heights.indices, id: \.self) { index in
                        Capsule()
                            .fill(Color(index == 3 ? AVEPalette.amber : AVEPalette.blue))
                            .frame(width: size * 0.072, height: size * heights[index])
                    }
                }
            }
            .frame(width: size, height: size)
        }
        .accessibilityLabel("AVE")
    }
}
#endif
