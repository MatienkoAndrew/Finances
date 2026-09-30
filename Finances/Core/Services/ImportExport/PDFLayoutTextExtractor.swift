import Foundation
import PDFKit
import CoreGraphics

struct PDFTextLine {
    let page: Int
    let y: CGFloat
    let text: String
}

/// Собирает текст страницы в визуальные строки по геометрии символов.
///
/// `page.string` не годится: на части страниц Kaspi PDFKit отдаёт текст
/// по колонкам («Покупка Снятие Покупка …»). Раньше строки собирались
/// из слов (`byWords`), но такой перебор выбрасывает пунктуацию —
/// терялись знаки `+`/`-`, скобки у валютной суммы и символы в названиях
/// мерчантов (`7-ELEVEN` → `7 ELEVEN`). Поэтому работаем посимвольно.
enum PDFLayoutTextExtractor {
    /// Допуск по вертикали, в пределах которого символы считаются одной строкой.
    private static let rowTolerance: CGFloat = 3

    /// Минимальный зазор между символами (в долях высоты символа), который считается пробелом.
    private static let spaceGapRatio: CGFloat = 0.2

    private typealias Glyph = (text: String, rect: CGRect)

    static func extractLines(from url: URL) throws -> [PDFTextLine] {
        guard let document = PDFDocument(url: url) else {
            throw PDFImporterError.failedToReadPDF
        }

        var result: [PDFTextLine] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let pageString = page.string,
                  !pageString.isEmpty else { continue }

            let pageHeight = page.bounds(for: .mediaBox).height

            for row in groupIntoRows(glyphs(on: page, text: pageString)) {
                let text = joinRow(row)
                guard !text.isEmpty else { continue }

                result.append(
                    PDFTextLine(
                        page: pageIndex + 1,
                        y: pageHeight - row[0].rect.midY,
                        text: text
                    )
                )
            }
        }

        return result
    }

    private static func glyphs(on page: PDFPage, text: String) -> [Glyph] {
        let nsString = text as NSString
        var glyphs: [Glyph] = []

        nsString.enumerateSubstrings(
            in: NSRange(location: 0, length: nsString.length),
            options: .byComposedCharacterSequences
        ) { substring, range, _, _ in
            guard let substring,
                  !substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let selection = page.selection(for: range) else { return }

            let rect = selection.bounds(for: page)
            guard !rect.isNull, !rect.isEmpty else { return }

            glyphs.append((text: substring, rect: rect))
        }

        return glyphs
    }

    private static func groupIntoRows(_ glyphs: [Glyph]) -> [[Glyph]] {
        let sorted = glyphs.sorted { lhs, rhs in
            if abs(lhs.rect.midY - rhs.rect.midY) > rowTolerance {
                return lhs.rect.midY > rhs.rect.midY
            }
            return lhs.rect.minX < rhs.rect.minX
        }

        var rows: [[Glyph]] = []

        for glyph in sorted {
            if let lastIndex = rows.indices.last,
               abs(rows[lastIndex][0].rect.midY - glyph.rect.midY) <= rowTolerance {
                rows[lastIndex].append(glyph)
            } else {
                rows.append([glyph])
            }
        }

        return rows
    }

    private static func joinRow(_ row: [Glyph]) -> String {
        var text = ""
        var previous: CGRect?

        for glyph in row.sorted(by: { $0.rect.minX < $1.rect.minX }) {
            if let previous {
                let gap = glyph.rect.minX - previous.maxX
                if gap > max(previous.height, glyph.rect.height) * spaceGapRatio {
                    text += " "
                }
            }
            text += glyph.text
            previous = glyph.rect
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
