/// Découpe une réponse en blocs (titres, listes, citations, code, paragraphes), comme l'affichent ChatGPT et Claude.
/// `Text(AttributedString(markdown:))` de SwiftUI ne rend que le formatage EN LIGNE (gras, italique, code) : les listes et
/// les titres doivent être découpés ici, puis chaque bloc rendu à part. Pur, testé ; volontairement limité au Markdown
/// courant des assistants : tableaux simples (maquette validée le 2026-10-23), pas de listes imbriquées.
public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bullet(String)
    case numbered(index: Int, text: String)
    case quote(String)
    case code(String)
    /// Tableau `| a | b |` dont la 2e ligne est le séparateur `|---|---|`. Chaque ligne a autant de cellules que l'en-tête.
    case table(header: [String], rows: [[String]])
}

public enum MarkdownBlocks {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?
        var tableLines: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        /// Un tableau n'en est un qu'avec sa ligne de séparation ; sinon (réponse encore en cours d'écriture, simple
        /// texte entre barres), les lignes restent du texte.
        func flushTable() {
            guard !tableLines.isEmpty else { return }
            defer { tableLines = [] }
            guard tableLines.count >= 2, isSeparator(tableLines[1]) else {
                paragraph.append(contentsOf: tableLines)
                return
            }
            flushParagraph()
            let header = cells(tableLines[0])
            let rows = tableLines.dropFirst(2).map { line -> [String] in
                let row = cells(line)
                return Array((row + Array(repeating: "", count: max(0, header.count - row.count))).prefix(header.count))
            }
            blocks.append(.table(header: header, rows: rows))
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if code == nil, line.hasPrefix("|") {
                tableLines.append(line)
                continue
            }
            flushTable()
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
        flushTable()
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }  // bloc non fermé : on le garde
        flushParagraph()
        return blocks
    }

    /// `| a | b |` → `["a", "b"]` (barres de bord facultatives).
    static func cells(_ line: String) -> [String] {
        var body = line.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        return body.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// `|---|:--:|` : seulement des tirets, deux-points, espaces et barres, avec au moins un tiret par cellule.
    static func isSeparator(_ line: String) -> Bool {
        let parts = cells(line)
        return !parts.isEmpty && parts.allSatisfy { part in
            part.contains("-") && part.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
        }
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
