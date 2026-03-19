import Foundation

enum PDFImporterError: LocalizedError {
    case failedToAccessFile
    case failedToReadPDF
    case noTransactionsFound

    var errorDescription: String? {
        switch self {
        case .failedToAccessFile:
            return "Не удалось получить доступ к файлу."
        case .failedToReadPDF:
            return "Не удалось прочитать PDF."
        case .noTransactionsFound:
            return "В PDF не найдено ни одной операции."
        }
    }
}

enum PDFImporter {
    static func importExpenses(from url: URL, existingExpenses: [Expense]) throws -> [Expense] {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let lines = try PDFLayoutTextExtractor.extractLines(from: url)
        let parsedRows = KaspiStatementParser.parse(lines: lines)

        guard !parsedRows.isEmpty else {
            throw PDFImporterError.noTransactionsFound
        }

        let existingFingerprints = Set(
            existingExpenses.compactMap { $0.fingerprint }
        )

        let newRows = parsedRows.filter { row in
            !existingFingerprints.contains(row.fingerprint)
        }

        let fileName = url.lastPathComponent
        let importedAt = Date()

        return newRows.map { row in
            Expense(
                date: row.date,
                amount: row.amount,
                accountCurrency: row.accountCurrency,
                operationType: row.operationType,
                details: row.details,
                foreignAmount: row.foreignAmount,
                foreignCurrency: row.foreignCurrency,
                category: nil,
                note: nil,
                fingerprint: row.fingerprint,
                sourceFileName: fileName,
                importedAt: importedAt
            )
        }
    }
}
