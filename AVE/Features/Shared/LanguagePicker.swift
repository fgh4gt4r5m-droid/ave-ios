#if os(iOS)
import AVECore
import SwiftUI

/// Langue choisie, partagée entre l'écran et le sélecteur.
public struct AVELanguageSelection: Equatable, Sendable {
    public var language: AVELanguage
    public init(language: AVELanguage = .french) { self.language = language }
}

/// Liste des langues avec statuts honnêtes (liste codée en dur, voir `LanguageCatalog`).
public struct LanguagePicker: View {
    @Binding var selection: AVELanguageSelection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.aveTheme) private var theme

    public init(selection: Binding<AVELanguageSelection>) {
        self._selection = selection
    }

    public var body: some View {
        NavigationStack {
            List(LanguageCatalog.builtIn) { option in
                Button {
                    selection.language = option.language
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name).font(.headline)
                            if let native = option.nativeName { Text(native).font(.subheadline).foregroundStyle(.secondary) }
                            Label(option.detail, systemImage: option.isAvailable ? "checkmark.circle" : "clock")
                                .font(.footnote)
                                .foregroundStyle(option.isAvailable ? Color.secondary : theme.warning)
                        }
                        Spacer()
                        if selection.language == option.language {
                            Image(systemName: "checkmark").accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selection.language == option.language ? .isSelected : [])
            }
            .navigationTitle("Langue")
            .navigationBarTitleDisplayModeInline()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }
}

private extension View {
    @ViewBuilder func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
#endif
