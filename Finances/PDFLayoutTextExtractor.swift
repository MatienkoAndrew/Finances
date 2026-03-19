import Foundation
import PDFKit
import CoreGraphics

struct PDFTextLine {
    let page: Int
    let y: CGFloat
    let text: String
}

enum PDFLayoutTextExtractor {
    static func extractLines(from url: URL) throws -> [PDFTextLine] {
        guard let document = PDFDocument(url: url) else {
            throw PDFImporterError.failedToReadPDF
        }

        var result: [PDFTextLine] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            let pageBounds = page.bounds(for: .mediaBox)

            guard let pageString = page.string, !pageString.isEmpty else { continue }

            let fullRange = NSRange(location: 0, length: (pageString as NSString).length)
            guard let fullSelection = page.selection(for: fullRange),
                  let attributed = fullSelection.attributedString else {
                continue
            }

            let nsString = attributed.string as NSString
            var fragments: [(text: String, rect: CGRect)] = []

            nsString.enumerateSubstrings(
                in: NSRange(location: 0, length: nsString.length),
                options: NSString.EnumerationOptions.byWords.union(.substringNotRequired)
            ) { _, range, _, _ in
                guard let selection = page.selection(for: range) else { return }

                let text = nsString.substring(with: range)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !text.isEmpty else { return }

                let bounds = selection.bounds(for: page)
                guard !bounds.isNull, !bounds.isEmpty else { return }

                fragments.append((text: text, rect: bounds))
            }

            let tolerance: CGFloat = 3
            var rows: [[(text: String, rect: CGRect)]] = []

            let sortedFragments = fragments.sorted { lhs, rhs in
                if abs(lhs.rect.midY - rhs.rect.midY) > tolerance {
                    return lhs.rect.midY > rhs.rect.midY
                }
                return lhs.rect.minX < rhs.rect.minX
            }

            for fragment in sortedFragments {
                if let lastIndex = rows.indices.last {
                    let lastY = rows[lastIndex].first!.rect.midY

                    if abs(lastY - fragment.rect.midY) <= tolerance {
                        rows[lastIndex].append(fragment)
                    } else {
                        rows.append([fragment])
                    }
                } else {
                    rows.append([fragment])
                }
            }

            for row in rows {
                let sortedRow = row.sorted { $0.rect.minX < $1.rect.minX }
                let lineText = sortedRow
                    .map(\.text)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !lineText.isEmpty else { continue }

                result.append(
                    PDFTextLine(
                        page: pageIndex + 1,
                        y: pageBounds.height - row[0].rect.midY,
                        text: lineText
                    )
                )
            }
        }

        return result
    }
}
