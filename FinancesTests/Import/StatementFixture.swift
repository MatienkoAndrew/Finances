import Foundation
import SwiftData
@testable import Finances

/// Собирает текст выписки Kaspi в том виде, в каком его отдаёт `PDFLayoutTextExtractor`,
/// и сразу считает итоги по типам и остатки — чтобы выписка была согласованной.
struct StatementFixture {
    struct Row {
        let date: String
        let amount: Double
        let operation: KaspiOperationType
        let details: String
        var foreign: (amount: Double, currency: String)?
        var isExchangeRateDifference = false
    }

    let start: String
    let end: String
    var opening: Double = 100_000
    var rows: [Row] = []

    init(from start: String, to end: String, opening: Double = 100_000) {
        self.start = start
        self.end = end
        self.opening = opening
    }

    @discardableResult
    mutating func purchase(_ date: String, _ amount: Double, _ details: String, fx: (Double, String)? = nil) -> Self {
        rows.append(Row(date: date, amount: -abs(amount), operation: .purchase, details: details, foreign: fx.map { (-abs($0.0), $0.1) }))
        return self
    }

    @discardableResult
    mutating func exchangeRateDifference(_ date: String, _ amount: Double, _ details: String) -> Self {
        rows.append(Row(date: date, amount: amount, operation: .purchase, details: details, isExchangeRateDifference: true))
        return self
    }

    @discardableResult
    mutating func row(_ date: String, _ amount: Double, _ operation: KaspiOperationType, _ details: String, fx: (Double, String)? = nil) -> Self {
        rows.append(Row(date: date, amount: amount, operation: operation, details: details, foreign: fx))
        return self
    }

    var closing: Double { opening + rows.reduce(0) { $0 + $1.amount } }

    var lines: [String] {
        var lines = [
            "Приложение к Справке №1 от 1 января 2026",
            "ВЫПИСКА",
            "по Kaspi Gold за период с \(start) по \(end)",
            "Доступно на \(end): \(Self.money(closing)) ₸ Валюта счета: теңге",
            "Краткое содержание операций по карте: Лимит на снятие наличности без комиссии:",
            "Доступно на \(start) \(Self.money(opening)) ₸ Остаток зарплатных денег 0,00 ₸"
        ]

        for type in KaspiOperationType.allCases {
            let total = rows.filter { $0.operation == type }.reduce(0) { $0 + $1.amount }
            lines.append("\(type.summaryTitle) \(Self.money(total)) ₸")
        }

        lines.append("Дата Сумма Операция Детали")

        for row in rows {
            lines.append("\(row.date) \(Self.money(row.amount)) ₸ \(row.operation.rawValue) \(row.details)")
            if let foreign = row.foreign {
                lines.append("(\(Self.money(foreign.amount)) \(foreign.currency))")
            }
            if row.isExchangeRateDifference {
                lines.append("Курсовая разница")
            }
        }

        lines.append("АО «Kaspi Bank», БИК CASPKZKA, www.kaspi.kz")
        return lines
    }

    var statement: KaspiStatement {
        KaspiStatementParser.parse(lines: Self.textLines(lines))
    }

    static func textLines(_ lines: [String]) -> [PDFTextLine] {
        lines.enumerated().map { PDFTextLine(page: 1, y: CGFloat($0.offset * 16), text: $0.element) }
    }

    /// «- 4 613,91» / «+ 4,57» — как в выписке.
    static func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","
        formatter.usesGroupingSeparator = true
        let number = formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        return "\(value < 0 ? "-" : "+") \(number)"
    }
}

/// Дата, как её хранит импорт: полдень по времени Kaspi.
func kaspiDay(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yy HH:mm"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = KaspiStatementParser.timeZone
    return formatter.date(from: "\(string) 12:00")!
}

/// Дата старого импорта: полночь в поясе, где делался импорт.
func legacyMidnight(_ string: String, in timeZone: TimeZone) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yy"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    return formatter.date(from: string)!
}

/// Изолированная среда: SwiftData в памяти, временная папка и свои `UserDefaults`
/// для истории импортов и журнала дублей.
@MainActor
final class ImportTestEnvironment {
    let container: ModelContainer
    let context: ModelContext
    let kaspi: Account

    init() throws {
        container = try ModelContainer(
            for: Transaction.self, Account.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        kaspi = Account(name: "Kaspi", currencyCode: "KZT", typeRaw: AccountType.bankCard.rawValue)
        context.insert(kaspi)
        try context.save()

        let id = UUID().uuidString
        ImportStorage.directory = FileManager.default.temporaryDirectory.appendingPathComponent("finances-tests-\(id)")
        ImportStorage.defaults = UserDefaults(suiteName: "finances-tests-\(id)")!
    }

    var transactions: [Transaction] { (try? context.fetch(FetchDescriptor<Transaction>())) ?? [] }
    var accounts: [Account] { (try? context.fetch(FetchDescriptor<Account>())) ?? [] }

    /// То же, что делает экран транзакций после чтения PDF.
    @discardableResult
    func importStatement(_ fixture: StatementFixture, fileName: String = "statement.pdf") throws -> PDFImportResult {
        let result = try PDFImporter.importStatement(
            fixture.statement,
            fileName: fileName,
            existingTransactions: transactions,
            accounts: accounts,
            rules: [],
            categories: [],
            rates: [],
            fallbackKztPerRub: 5
        )
        result.accountsToCreate.forEach { context.insert($0) }
        result.transactions.forEach { context.insert($0) }
        try context.save()

        let removed = DuplicateCleaner.autoCleanupIfEnabled(context: context)
        ImportHistory.add(ImportRecord(
            importedAt: result.importedAt,
            fileName: result.fileName,
            createdAccountKeys: result.accountsToCreate.map(ImportHistory.key(of:)),
            modifications: result.modifications,
            removedDuplicateIDs: removed.map(\.id)
        ))
        return result
    }

    /// Операция, как её сохранял старый импорт (до исправлений): знак всегда «-» у покупок.
    @discardableResult
    func insertLegacy(
        date: Date,
        amount: Double,
        details: String,
        kind: TransactionKind = .expense,
        foreign: (Double, String)? = nil,
        importedAt: Date,
        fingerprint: String = UUID().uuidString
    ) -> Transaction {
        let transaction = Transaction(
            date: date,
            kindRaw: kind.rawValue,
            amount: abs(amount),
            currencyCode: "KZT",
            details: details,
            foreignAmount: foreign.map { abs($0.0) },
            foreignCurrencyCode: foreign?.1,
            rubAmount: abs(amount) / 5,
            categoryName: kind == .expense ? "Еда" : nil,
            fingerprint: fingerprint,
            sourceFileName: "legacy.pdf",
            importedAt: importedAt,
            createdAt: importedAt,
            fromAccount: kind == .expense ? kaspi : nil,
            toAccount: kind == .income ? kaspi : nil
        )
        context.insert(transaction)
        return transaction
    }

    /// Снимок базы для сравнения «до» и «после».
    var state: [String] {
        transactions.map { t in
            [
                t.fingerprint ?? "-", t.details, t.kindRaw,
                String(format: "%.2f", t.amount), String(format: "%.2f", t.rubAmount ?? -1),
                t.categoryName ?? "-", t.note ?? "-",
                t.fromAccount?.name ?? "-", t.toAccount?.name ?? "-",
                "\(t.date.timeIntervalSinceReferenceDate)"
            ].joined(separator: "|")
        }
        .sorted()
    }
}
