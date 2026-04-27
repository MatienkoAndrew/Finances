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
        categories: [ExpenseCategoryItem],
        rates: [ExchangeRateEntry],
        fallbackKztPerRub: Double?
    ) throws -> PDFImportResult {
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

        var existingFingerprints = Set(
            existingTransactions.compactMap(\.fingerprint)
        )

        let fileName = url.lastPathComponent
        let importedAt = Date()

        var workingAccounts = accounts
        var accountsToCreate: [Account] = []
        var importedTransactions: [Transaction] = []

        for row in parsedRows {
            guard !existingFingerprints.contains(row.fingerprint) else {
                continue
            }

            let transaction = makeTransaction(
                from: row,
                accounts: &workingAccounts,
                accountsToCreate: &accountsToCreate,
                rules: rules,
                categories: categories,
                rates: rates,
                fallbackKztPerRub: fallbackKztPerRub,
                fileName: fileName,
                importedAt: importedAt
            )

            importedTransactions.append(transaction)
            existingFingerprints.insert(row.fingerprint)
        }

        guard !importedTransactions.isEmpty else {
            throw PDFImporterError.noNewTransactionsFound
        }

        return PDFImportResult(
            accountsToCreate: accountsToCreate,
            transactions: importedTransactions
        )
    }

    private static func makeTransaction(
        from row: ParsedStatementRow,
        accounts: inout [Account],
        accountsToCreate: inout [Account],
        rules: [CategoryRule],
        categories: [ExpenseCategoryItem],
        rates: [ExchangeRateEntry],
        fallbackKztPerRub: Double?,
        fileName: String,
        importedAt: Date
    ) -> Transaction {
        let sourceCurrency = CurrencyDisplay.normalizedCode(from: row.accountCurrency)
        let foreignCurrency = row.foreignCurrency.map { CurrencyDisplay.normalizedCode(from: $0) }

        let absoluteAmount = abs(row.amount)
        let absoluteForeignAmount = row.foreignAmount.map(abs)

        let rubAmount = makeRubAmount(
            amount: absoluteAmount,
            currencyCode: sourceCurrency,
            date: row.date,
            rates: rates,
            fallbackKztPerRub: fallbackKztPerRub
        )

        let kaspiAccount = AccountLookup.kaspi(in: accounts)

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
                    rules: rules,
                    existingCategories: categories
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

            let destinationAccount = resolveOrCreateCashAccount(
                currencyCode: destinationCurrency,
                accounts: &accounts,
                accountsToCreate: &accountsToCreate
            )

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
                toAccount: destinationAccount
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
                        rules: rules,
                        existingCategories: categories
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
                        rules: rules,
                        existingCategories: categories
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

    private static func makeRubAmount(
        amount: Double,
        currencyCode: String,
        date: Date,
        rates: [ExchangeRateEntry],
        fallbackKztPerRub: Double?
    ) -> Double? {
        switch CurrencyDisplay.normalizedCode(from: currencyCode) {
        case "RUB":
            return amount

        case "KZT":
            return HistoricalCurrencyConverter.rubAmount(
                for: amount,
                on: date,
                rates: rates,
                fallbackKztPerRub: fallbackKztPerRub
            )

        default:
            return nil
        }
    }

    @discardableResult
    private static func resolveOrCreateCashAccount(
        currencyCode: String,
        accounts: inout [Account],
        accountsToCreate: inout [Account]
    ) -> Account {
        let normalized = CurrencyDisplay.normalizedCode(from: currencyCode)

        if let existing = accounts.first(where: {
            CurrencyDisplay.normalizedCode(from: $0.currencyCode) == normalized &&
            $0.type == .cash
        }) {
            return existing
        }

        let newAccount = Account(
            name: "Cash \(normalized)",
            currencyCode: normalized,
            typeRaw: AccountType.cash.rawValue,
            note: "Создан автоматически при импорте PDF"
        )

        accounts.append(newAccount)
        accountsToCreate.append(newAccount)
        return newAccount
    }
}
