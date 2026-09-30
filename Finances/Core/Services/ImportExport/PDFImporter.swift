import Foundation
import SwiftData

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
    static let exchangeRateDifferenceNote = "Курсовая разница"

    /// Сколько последних дней периода выписки считаются «в обработке».
    /// Для валютных операций Kaspi показывает там предварительную сумму в тенге,
    /// а в следующей выписке — окончательную (разница — единицы и десятки тенге).
    private static let pendingWindowDays = 4

    /// Импортирует выписку Kaspi Gold.
    ///
    /// Новые операции возвращаются в `transactions` — их нужно вставить в контекст.
    /// Уже существующие совпавшие транзакции обновляются на месте (уточнённая сумма,
    /// исправленный знак «Курсовой разницы»), поэтому после вызова контекст нужно сохранить.
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
        let statement = KaspiStatementParser.parse(lines: lines)
        let rows = statement.rows

        guard !rows.isEmpty else {
            throw PDFImporterError.noTransactionsFound
        }

        let context = ImportContext(
            kaspiAccount: AccountLookup.kaspi(in: accounts),
            rules: rules,
            categories: categories,
            rates: rates,
            fallbackKztPerRub: fallbackKztPerRub,
            fileName: url.lastPathComponent,
            importedAt: Date(),
            settledBefore: settledBoundary(for: statement)
        )

        let candidates = matchCandidates(
            existingTransactions,
            statement: statement,
            kaspiAccount: context.kaspiAccount
        )

        let matching = StatementDeduplicator.match(
            rows: rows,
            existing: candidates.map { snapshot(of: $0, kaspiAccount: context.kaspiAccount) }
        )

        var settledCount = 0
        var repairedCount = 0

        for match in matching.matches {
            let outcome = update(
                candidates[match.existingIndex],
                with: rows[match.rowIndex],
                context: context
            )
            if outcome.amountSettled { settledCount += 1 }
            if outcome.repaired { repairedCount += 1 }
        }

        let newRows = matching.unmatchedRowIndices.map { rows[$0] }
        let fingerprints = StatementDeduplicator.fingerprints(
            for: newRows,
            avoiding: Set(existingTransactions.compactMap(\.fingerprint))
        )
        var workingAccounts = accounts
        var accountsToCreate: [Account] = []

        let newTransactions = zip(newRows, fingerprints).map { row, fingerprint in
            makeTransaction(
                from: row,
                fingerprint: fingerprint,
                context: context,
                accounts: &workingAccounts,
                accountsToCreate: &accountsToCreate
            )
        }

        guard !newTransactions.isEmpty || settledCount > 0 || repairedCount > 0 else {
            throw PDFImporterError.noNewTransactionsFound
        }

        return PDFImportResult(
            accountsToCreate: accountsToCreate,
            transactions: newTransactions,
            skippedDuplicatesCount: matching.matches.count,
            settledAmountsCount: settledCount,
            repairedCount: repairedCount,
            mismatchedOperationTypes: statement.mismatchedTypes.map(\.summaryTitle),
            unrecognizedLinesCount: statement.unrecognizedLines.count
        )
    }

    // MARK: - Matching

    private struct ImportContext {
        let kaspiAccount: Account?
        let rules: [CategoryRule]
        let categories: [ExpenseCategoryItem]
        let rates: [ExchangeRateEntry]
        let fallbackKztPerRub: Double?
        let fileName: String
        let importedAt: Date
        /// Операции до этой даты (не включительно) уже проведены окончательно.
        let settledBefore: Date

        func isSettled(_ row: ParsedStatementRow) -> Bool {
            row.date < settledBefore
        }
    }

    private static func settledBoundary(for statement: KaspiStatement) -> Date {
        let calendar = KaspiStatementParser.calendar
        let periodEnd = statement.periodEnd ?? statement.rows.map(\.date).max() ?? Date()
        let lastDay = calendar.startOfDay(for: periodEnd)
        return calendar.date(byAdding: .day, value: -(pendingWindowDays - 1), to: lastDay) ?? lastDay
    }

    /// Транзакции, с которыми имеет смысл сравнивать строки выписки:
    /// по счёту Kaspi (или созданные импортом) и рядом с периодом выписки. Окно с запасом:
    /// точный день всё равно сверяет `StatementDeduplicator`.
    private static func matchCandidates(
        _ transactions: [Transaction],
        statement: KaspiStatement,
        kaspiAccount: Account?
    ) -> [Transaction] {
        let calendar = KaspiStatementParser.calendar
        let rowDates = statement.rows.map(\.date)

        guard let firstDate = statement.periodStart ?? rowDates.min(),
              let lastDate = statement.periodEnd ?? rowDates.max(),
              let lowerBound = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: firstDate)),
              let upperBound = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: lastDate)) else {
            return []
        }

        return transactions.filter { transaction in
            guard transaction.date >= lowerBound, transaction.date < upperBound else { return false }
            return transaction.fingerprint != nil
                || isKaspi(transaction.fromAccount, kaspiAccount)
                || isKaspi(transaction.toAccount, kaspiAccount)
        }
    }

    static func snapshot(of transaction: Transaction, kaspiAccount: Account?) -> TransactionSnapshot {
        TransactionSnapshot(
            date: transaction.date,
            details: transaction.details,
            amount: abs(transaction.amount),
            currencyCode: transaction.currencyCode,
            foreignAmount: transaction.foreignAmount,
            foreignCurrencyCode: transaction.foreignCurrencyCode,
            direction: direction(of: transaction, kaspiAccount: kaspiAccount),
            wasImported: transaction.fingerprint != nil
        )
    }

    private static func direction(of transaction: Transaction, kaspiAccount: Account?) -> Int {
        switch transaction.kind {
        case .expense:
            return -1
        case .income:
            return 1
        case .transfer:
            if isKaspi(transaction.toAccount, kaspiAccount) { return 1 }
            return -1
        }
    }

    private static func isKaspi(_ account: Account?, _ kaspiAccount: Account?) -> Bool {
        guard let account, let kaspiAccount else { return false }
        return account.persistentModelID == kaspiAccount.persistentModelID
    }

    // MARK: - Updating existing

    private struct UpdateOutcome {
        var amountSettled = false
        var repaired = false
    }

    private static func update(
        _ transaction: Transaction,
        with row: ParsedStatementRow,
        context: ImportContext
    ) -> UpdateOutcome {
        var outcome = UpdateOutcome()

        // Старый парсер игнорировал знак и записывал «+» по покупке
        // (курсовая разница, возврат) как расход.
        if row.operationType == .purchase || row.operationType == .misc {
            if row.amount > 0, transaction.kind == .expense {
                transaction.kind = .income
                transaction.toAccount = transaction.fromAccount ?? context.kaspiAccount
                transaction.fromAccount = nil
                if transaction.isCategoryManuallySet != true {
                    transaction.categoryName = nil
                    transaction.subcategoryName = nil
                }
                outcome.repaired = true
            } else if row.amount < 0, transaction.kind == .income {
                transaction.kind = .expense
                transaction.fromAccount = transaction.toAccount ?? context.kaspiAccount
                transaction.toAccount = nil
                if transaction.categoryName == nil {
                    transaction.categoryName = matchCategory(for: row, context: context)
                }
                outcome.repaired = true
            }
        }

        if row.isExchangeRateDifference, (transaction.note ?? "").isEmpty {
            transaction.note = exchangeRateDifferenceNote
            outcome.repaired = true
        }

        // Предварительная сумма в тенге из прошлой выписки → окончательная.
        let settledAmount = abs(row.amount)
        if context.isSettled(row),
           CurrencyDisplay.normalizedCode(from: transaction.currencyCode) == CurrencyDisplay.normalizedCode(from: row.accountCurrency),
           abs(transaction.amount - settledAmount) >= 0.005 {
            if let toCurrency = transaction.toCurrencyCode,
               CurrencyDisplay.normalizedCode(from: toCurrency) == CurrencyDisplay.normalizedCode(from: transaction.currencyCode) {
                transaction.toAmount = settledAmount
            }
            transaction.amount = settledAmount
            transaction.rubAmount = makeRubAmount(
                amount: settledAmount,
                currencyCode: transaction.currencyCode,
                date: transaction.date,
                context: context
            )
            outcome.amountSettled = true
        }

        return outcome
    }

    // MARK: - Creating new

    private static func makeTransaction(
        from row: ParsedStatementRow,
        fingerprint: String,
        context: ImportContext,
        accounts: inout [Account],
        accountsToCreate: inout [Account]
    ) -> Transaction {
        let sourceCurrency = CurrencyDisplay.normalizedCode(from: row.accountCurrency)
        let foreignCurrency = row.foreignCurrency.map { CurrencyDisplay.normalizedCode(from: $0) }
        let absoluteAmount = abs(row.amount)
        let isCredit = row.amount > 0
        let kaspiAccount = context.kaspiAccount

        let kind: TransactionKind
        var fromAccount: Account?
        var toAccount: Account?
        var toAmount: Double?
        var toCurrencyCode: String?
        var categoryName: String?

        switch (row.operationType, isCredit) {
        case (.withdrawal, false):
            // Снятие наличных — перевод с Kaspi на кошелёк наличных в валюте выдачи.
            let destinationCurrency = foreignCurrency ?? sourceCurrency
            kind = .transfer
            fromAccount = kaspiAccount
            toAccount = resolveOrCreateCashAccount(
                currencyCode: destinationCurrency,
                accounts: &accounts,
                accountsToCreate: &accountsToCreate
            )
            toAmount = abs(row.foreignAmount ?? row.amount)
            toCurrencyCode = destinationCurrency

        case (.transfer, false):
            kind = .transfer
            fromAccount = kaspiAccount

        case (_, true):
            kind = .income
            toAccount = kaspiAccount

        case (_, false):
            kind = .expense
            fromAccount = kaspiAccount
            categoryName = matchCategory(for: row, context: context)
        }

        return Transaction(
            date: row.date,
            kindRaw: kind.rawValue,
            amount: absoluteAmount,
            currencyCode: sourceCurrency,
            toAmount: toAmount,
            toCurrencyCode: toCurrencyCode,
            details: row.details,
            foreignAmount: row.foreignAmount.map(abs),
            foreignCurrencyCode: foreignCurrency,
            rubAmount: makeRubAmount(
                amount: absoluteAmount,
                currencyCode: sourceCurrency,
                date: row.date,
                context: context
            ),
            categoryName: categoryName,
            note: row.isExchangeRateDifference ? exchangeRateDifferenceNote : nil,
            fingerprint: fingerprint,
            sourceFileName: context.fileName,
            importedAt: context.importedAt,
            createdAt: context.importedAt,
            fromAccount: fromAccount,
            toAccount: toAccount
        )
    }

    private static func matchCategory(for row: ParsedStatementRow, context: ImportContext) -> String? {
        CategoryRuleEngine.matchCategoryName(
            operationType: row.operationType.rawValue,
            details: row.details,
            rules: context.rules,
            existingCategories: context.categories
        )
    }

    private static func makeRubAmount(
        amount: Double,
        currencyCode: String,
        date: Date,
        context: ImportContext
    ) -> Double? {
        switch CurrencyDisplay.normalizedCode(from: currencyCode) {
        case "RUB":
            return amount

        case "KZT":
            return HistoricalCurrencyConverter.rubAmount(
                for: amount,
                on: date,
                rates: context.rates,
                fallbackKztPerRub: context.fallbackKztPerRub
            )

        default:
            return nil
        }
    }

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
