/// Découpe une réponse en blocs (titres, listes, citations, code, paragraphes), comme l'affichent ChatGPT et Claude.
/// `Text(AttributedString(markdown:))` de SwiftUI ne rend que le formatage EN LIGNE (gras, italique, code) : les listes et
/// les titres doivent être découpés ici, puis chaque bloc rendu à part. Pur, testé ; volontairement limité au Markdown
/// courant des assistants (pas de tableaux ni de listes imbriquées pour l'instant).
public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bullet(String)
    case numbered(index: Int, text: String)
    case quote(String)
    case code(String)
}

public enum MarkdownBlocks {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(rawLine)
                continue
            }
            if line.isEmpty {
                flushParagraph()
                continue
            }
            if let heading = heading(line) {
                flushParagraph()
                blocks.append(heading)
            } else if let item = prefixed(line, by: ["- ", "* ", "• "]) {
                flushParagraph()
                blocks.append(.bullet(item))
            } else if let item = numbered(line) {
                flushParagraph()
                blocks.append(.numbered(index: item.index, text: item.text))
            } else if let quote = prefixed(line, by: ["> "]) {
                flushParagraph()
                blocks.append(.quote(quote))
            } else {
                paragraph.append(line)
            }
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }  // bloc non fermé : on le garde
        flushParagraph()
        return blocks
    }

    private static func prefixed(_ line: String, by markers: [String]) -> String? {
        for marker in markers where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...3).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return .heading(level: hashes, text: String(line.dropFirst(hashes + 1)).trimmingCharacters(in: .whitespaces))
    }

    private static func numbered(_ line: String) -> (index: Int, text: String)? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3, let index = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")", rest.dropFirst().first == " " else { return nil }
        return (index, String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }
}
