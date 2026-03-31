import Foundation

enum PDFImporterError: LocalizedError {
    case failedToAccessFile
    case failedToReadPDF
    case noTransactionsFound
    case noNewTransactionsFound

    var errorDescription: String? {
        switch self {
        case .failedToAccessFile:
            return "Не удалось получить доступ к файлу."
        case .failedToReadPDF:
            return "Не удалось прочитать PDF."
        case .noTransactionsFound:
            return "В PDF не найдено ни одной операции."
        case .noNewTransactionsFound:
            return "Все операции из этого PDF уже были импортированы."
        }
    }
}


enum PDFImporter {
    static func importTransactions(
        from url: URL,
        existingTransactions: [Transaction],
        accounts: [Account],
        rules: [CategoryRule],
        rates: [ExchangeRateEntry],
        fallbackKztPerRub: Double?
    ) throws -> [Transaction] {
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
            existingTransactions.compactMap(\.fingerprint)
        )

        let newRows = parsedRows.filter { row in
            !existingFingerprints.contains(row.fingerprint)
        }

        guard !newRows.isEmpty else {
            throw PDFImporterError.noNewTransactionsFound
        }

        let fileName = url.lastPathComponent
        let importedAt = Date()

        let kaspiAccount = AccountLookup.kaspi(in: accounts)

        return newRows.map { row in
            let sourceCurrency = normalizedCurrencyCode(row.accountCurrency)
            let foreignCurrency = row.foreignCurrency.map(normalizedCurrencyCode)

            let absoluteAmount = abs(row.amount)
            let absoluteForeignAmount = row.foreignAmount.map(abs)

            let rubAmount = makeRubAmount(
                amount: absoluteAmount,
                currencyCode: sourceCurrency,
                date: row.date,
                rates: rates,
                fallbackKztPerRub: fallbackKztPerRub
            )

            switch row.operationType {
            case "Покупка":
                return Transaction(
                    date: row.date,
                    kindRaw: TransactionKind.expense.rawValue,
                    amount: absoluteAmount,
                    currencyCode: sourceCurrency,
                    details: row.details,
                    foreignAmount: absoluteForeignAmount,
                    foreignCurrencyCode: foreignCurrency,
                    rubAmount: rubAmount,
                    categoryName: CategoryRuleEngine.matchCategoryName(
                        operationType: row.operationType,
                        details: row.details,
                        rules: rules
                    ),
                    note: nil,
                    fingerprint: row.fingerprint,
                    sourceFileName: fileName,
                    importedAt: importedAt,
                    createdAt: importedAt,
                    fromAccount: kaspiAccount,
                    toAccount: nil
                )

            case "Пополнение":
                return Transaction(
                    date: row.date,
                    kindRaw: TransactionKind.income.rawValue,
                    amount: absoluteAmount,
                    currencyCode: sourceCurrency,
                    details: row.details,
                    foreignAmount: absoluteForeignAmount,
                    foreignCurrencyCode: foreignCurrency,
                    rubAmount: rubAmount,
                    categoryName: nil,
                    note: nil,
                    fingerprint: row.fingerprint,
                    sourceFileName: fileName,
                    importedAt: importedAt,
                    createdAt: importedAt,
                    fromAccount: nil,
                    toAccount: kaspiAccount
                )

            case "Снятие":
                let destinationCurrency = foreignCurrency ?? sourceCurrency
                let destinationAmount = abs(row.foreignAmount ?? row.amount)

                return Transaction(
                    date: row.date,
                    kindRaw: TransactionKind.transfer.rawValue,
                    amount: absoluteAmount,
                    currencyCode: sourceCurrency,
                    toAmount: destinationAmount,
                    toCurrencyCode: destinationCurrency,
                    details: row.details,
                    foreignAmount: absoluteForeignAmount,
                    foreignCurrencyCode: foreignCurrency,
                    rubAmount: rubAmount,
                    categoryName: nil,
                    note: nil,
                    fingerprint: row.fingerprint,
                    sourceFileName: fileName,
                    importedAt: importedAt,
                    createdAt: importedAt,
                    fromAccount: kaspiAccount,
                    toAccount: AccountLookup.cashAccount(currencyCode: destinationCurrency, in: accounts)
                )

            case "Перевод":
                return Transaction(
                    date: row.date,
                    kindRaw: TransactionKind.transfer.rawValue,
                    amount: absoluteAmount,
                    currencyCode: sourceCurrency,
                    toAmount: nil,
                    toCurrencyCode: nil,
                    details: row.details,
                    foreignAmount: absoluteForeignAmount,
                    foreignCurrencyCode: foreignCurrency,
                    rubAmount: rubAmount,
                    categoryName: nil,
                    note: nil,
                    fingerprint: row.fingerprint,
                    sourceFileName: fileName,
                    importedAt: importedAt,
                    createdAt: importedAt,
                    fromAccount: kaspiAccount,
                    toAccount: nil
                )

            case "Разное":
                if row.amount >= 0 {
                    return Transaction(
                        date: row.date,
                        kindRaw: TransactionKind.income.rawValue,
                        amount: absoluteAmount,
                        currencyCode: sourceCurrency,
                        details: row.details,
                        foreignAmount: absoluteForeignAmount,
                        foreignCurrencyCode: foreignCurrency,
                        rubAmount: rubAmount,
                        categoryName: nil,
                        note: nil,
                        fingerprint: row.fingerprint,
                        sourceFileName: fileName,
                        importedAt: importedAt,
                        createdAt: importedAt,
                        fromAccount: nil,
                        toAccount: kaspiAccount
                    )
                } else {
                    return Transaction(
                        date: row.date,
                        kindRaw: TransactionKind.expense.rawValue,
                        amount: absoluteAmount,
                        currencyCode: sourceCurrency,
                        details: row.details,
                        foreignAmount: absoluteForeignAmount,
                        foreignCurrencyCode: foreignCurrency,
                        rubAmount: rubAmount,
                        categoryName: CategoryRuleEngine.matchCategoryName(
                            operationType: row.operationType,
                            details: row.details,
                            rules: rules
                        ),
                        note: nil,
                        fingerprint: row.fingerprint,
                        sourceFileName: fileName,
                        importedAt: importedAt,
                        createdAt: importedAt,
                        fromAccount: kaspiAccount,
                        toAccount: nil
                    )
                }

            default:
                if row.amount >= 0 {
                    return Transaction(
                        date: row.date,
                        kindRaw: TransactionKind.income.rawValue,
                        amount: absoluteAmount,
                        currencyCode: sourceCurrency,
                        details: row.details,
                        foreignAmount: absoluteForeignAmount,
                        foreignCurrencyCode: foreignCurrency,
                        rubAmount: rubAmount,
                        categoryName: nil,
                        note: nil,
                        fingerprint: row.fingerprint,
                        sourceFileName: fileName,
                        importedAt: importedAt,
                        createdAt: importedAt,
                        fromAccount: nil,
                        toAccount: kaspiAccount
                    )
                } else {
                    return Transaction(
                        date: row.date,
                        kindRaw: TransactionKind.expense.rawValue,
                        amount: absoluteAmount,
                        currencyCode: sourceCurrency,
                        details: row.details,
                        foreignAmount: absoluteForeignAmount,
                        foreignCurrencyCode: foreignCurrency,
                        rubAmount: rubAmount,
                        categoryName: CategoryRuleEngine.matchCategoryName(
                            operationType: row.operationType,
                            details: row.details,
                            rules: rules
                        ),
                        note: nil,
                        fingerprint: row.fingerprint,
                        sourceFileName: fileName,
                        importedAt: importedAt,
                        createdAt: importedAt,
                        fromAccount: kaspiAccount,
                        toAccount: nil
                    )
                }
            }
        }
    }

    private static func makeRubAmount(
        amount: Double,
        currencyCode: String,
        date: Date,
        rates: [ExchangeRateEntry],
        fallbackKztPerRub: Double?
    ) -> Double? {
        if currencyCode == "₽" {
            return amount
        }

        if currencyCode == "₸" {
            return HistoricalCurrencyConverter.rubAmount(
                for: amount,
                on: date,
                rates: rates,
                fallbackKztPerRub: fallbackKztPerRub
            )
        }

        return nil
    }

    private static func normalizedCurrencyCode(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "KZT", "₸":
            return "₸"
        case "RUB", "RUR", "₽":
            return "₽"
        case "VND", "₫":
            return "₫"
        case "USD", "$":
            return "$"
        case "EUR", "€":
            return "€"
        case "JPY", "¥":
            return "¥"
        default:
            return value
        }
    }
}
