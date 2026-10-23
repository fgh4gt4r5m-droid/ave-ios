#if os(iOS)
import SwiftUI

/// Réponse mise en forme : chaque bloc (`MarkdownBlocks`) rendu à part, le formatage en ligne (gras, italique, code,
/// liens) laissé à `AttributedString`. Dynamic Type respecté : seules des tailles sémantiques sont utilisées.
struct RichText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let s):
                    inline(s)
                case .heading(let level, let s):
                    inline(s).font(level == 1 ? .title3.weight(.bold) : .headline)
                        .accessibilityAddTraits(.isHeader)
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").accessibilityHidden(true)
                        inline(s)
                    }
                case .numbered(let index, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index).").monospacedDigit()
                        inline(s)
                    }
                case .quote(let s):
                    inline(s)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5).fill(.tertiary).frame(width: 3)
                        }
                case .code(let s):
                    ScrollView(.horizontal) {
                        Text(s)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
                case .table(let header, let rows):
                    table(header: header, rows: rows)
                }
            }
        }
        .textSelection(.enabled)
    }

    /// Tableau simple : un tableau plus large que l'écran défile DANS la réponse, jamais l'écran (maquette 3).
    private func table(header: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Pas de modificateur sur un `GridRow` : la grille ne le reconnaîtrait plus comme une ligne.
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        inline(cell).font(.subheadline.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 8)
                            .frame(maxWidth: 220, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            inline(cell).font(.subheadline).padding(.horizontal, 10).padding(.vertical, 8)
                                .frame(maxWidth: 220, alignment: .leading)
                        }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 1))
            .clipShape(.rect(cornerRadius: 12))
            .padding(1)
        }
        .scrollIndicators(.hidden)
    }

    private func inline(_ s: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return Text((try? AttributedString(markdown: s, options: options)) ?? AttributedString(s))
    }
}
#endif
