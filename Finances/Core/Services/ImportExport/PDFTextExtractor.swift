//
//  PDFTextExtractor.swift
//  Finances
//
//  Created by Андрей Матиенко on 19.03.2026.
//


import Foundation
import PDFKit

enum PDFTextExtractor {
    static func extractText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw PDFImporterError.failedToReadPDF
        }

        var fullText: [String] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let pageText = page.string else {
                continue
            }

            fullText.append(pageText)
        }

        let result = fullText.joined(separator: "\n")
        if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PDFImporterError.failedToReadPDF
        }

        return result
    }
}