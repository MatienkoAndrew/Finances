import Foundation
import SwiftData

/// Поля транзакции, которые импорт может поправить у уже существующей операции
/// (уточнённая сумма, исправленный знак, заметка «Курсовая разница»).
struct TransactionFieldValues: Codable, Equatable {
    var kindRaw: String
    var amount: Double
    var toAmount: Double?
    var rubAmount: Double?
    var categoryName: String?
    var subcategoryName: String?
    var isCategoryManuallySet: Bool?
    var note: String?
    var fromAccountKey: String?
    var toAccountKey: String?

    init(_ transaction: Transaction) {
        kindRaw = transaction.kindRaw
        amount = transaction.amount
        toAmount = transaction.toAmount
        rubAmount = transaction.rubAmount
        categoryName = transaction.categoryName
        subcategoryName = transaction.subcategoryName
        isCategoryManuallySet = transaction.isCategoryManuallySet
        note = transaction.note
        fromAccountKey = transaction.fromAccount.map(ImportHistory.key(of:))
        toAccountKey = transaction.toAccount.map(ImportHistory.key(of:))
    }

    func apply(to transaction: Transaction, accountsByKey: [String: Account]) {
        transaction.kindRaw = kindRaw
        transaction.amount = amount
        transaction.toAmount = toAmount
        transaction.rubAmount = rubAmount
        transaction.categoryName = categoryName
        transaction.subcategoryName = subcategoryName
        transaction.isCategoryManuallySet = isCategoryManuallySet
        transaction.note = note
        transaction.fromAccount = fromAccountKey.flatMap { accountsByKey[$0] }
        transaction.toAccount = toAccountKey.flatMap { accountsByKey[$0] }
    }
}

struct TransactionModification: Codable {
    /// `ImportHistory.key(of:)` — `PersistentIdentifier` после чтения из JSON
    /// сравнивается с живыми объектами ненадёжно.
    let transactionKey: String
    let before: TransactionFieldValues
    let after: TransactionFieldValues
}

/// Что сделал один импорт PDF, кроме добавления операций, — чтобы его можно было отменить целиком.
/// Сами добавленные операции узнаются по `Transaction.importedAt`.
struct ImportRecord: Codable, Identifiable {
    var id: Date { importedAt }

    let importedAt: Date
    let fileName: String
    /// `ImportHistory.key(of:)` созданных импортом счетов.
    let createdAccountKeys: [String]
    let modifications: [TransactionModification]
    /// Дубли, удалённые автоочисткой сразу после импорта (id записей `DuplicateRemovalLog`).
    let removedDuplicateIDs: [UUID]
}

/// Один импорт в истории.
struct ImportBatch: Identifiable {
    var id: Date { importedAt }

    let importedAt: Date
    let fileName: String?
    let transactionCount: Int
    let firstDate: Date?
    let lastDate: Date?
    /// Есть только у импортов, сделанных после появления отмены.
    let record: ImportRecord?
}

struct ImportUndoSummary {
    var deletedCount = 0
    var revertedCount = 0
    var restoredDuplicatesCount = 0
    /// Поправленные импортом операции, которые потом изменили вручную, — их не трогаем.
    var skippedChangedCount = 0

    var message: String {
        var parts = ["Удалено операций: \(deletedCount)"]
        if revertedCount > 0 {
            parts.append("возвращены прежние значения: \(revertedCount)")
        }
        if restoredDuplicatesCount > 0 {
            parts.append("возвращены удалённые дубли: \(restoredDuplicatesCount)")
        }
        var message = parts.joined(separator: ", ") + "."
        if skippedChangedCount > 0 {
            message += "\nНе тронуты операции, изменённые после импорта: \(skippedChangedCount)."
        }
        return message
    }
}

/// Где лежат служебные файлы импорта (история, удалённые дубли) и их настройки.
/// Тесты подменяют на временную папку и отдельный набор `UserDefaults`.
@MainActor
enum ImportStorage {
    static var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    static var defaults = UserDefaults.standard

    static func fileURL(_ name: String) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }
}

/// История импортов PDF и их отмена.
@MainActor
enum ImportHistory {
    private static let limit = 100

    private static var fileURL: URL {
        ImportStorage.fileURL("import-history.json")
    }

    // MARK: - Records

    static func add(_ record: ImportRecord) {
        save(Array(([record] + loadRecords()).prefix(limit)))
    }

    static func loadRecords() -> [ImportRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        // Формат дат по умолчанию: `importedAt` сравнивается с полем транзакции точно.
        return (try? JSONDecoder().decode([ImportRecord].self, from: data)) ?? []
    }

    private static func removeRecord(importedAt: Date) {
        save(loadRecords().filter { $0.importedAt != importedAt })
    }

    private static func save(_ records: [ImportRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Keys

    /// Стабильный ключ операции: `createdAt` и `fingerprint` не меняются после создания.
    nonisolated static func key(of transaction: Transaction) -> String {
        "\(transaction.createdAt.timeIntervalSinceReferenceDate)|\(transaction.fingerprint ?? "-")"
    }

    nonisolated static func key(of account: Account) -> String {
        "\(account.createdAt.timeIntervalSinceReferenceDate)|\(account.name)"
    }

    // MARK: - Batches

    /// Все импорты — и новые, и сделанные до появления истории: операции одного
    /// импорта имеют одинаковый `importedAt`. Новые сверху.
    static func batches(in transactions: [Transaction]) -> [ImportBatch] {
        let records = Dictionary(loadRecords().map { ($0.importedAt, $0) }, uniquingKeysWith: { first, _ in first })
        let grouped = Dictionary(grouping: transactions.filter { $0.importedAt != nil }, by: { $0.importedAt! })

        var batches = grouped.map { importedAt, members in
            let dates = members.map(\.date)
            return ImportBatch(
                importedAt: importedAt,
                fileName: members.first?.sourceFileName ?? records[importedAt]?.fileName,
                transactionCount: members.count,
                firstDate: dates.min(),
                lastDate: dates.max(),
                record: records[importedAt]
            )
        }

        // Импорт мог ничего не добавить, а только уточнить суммы — его тоже можно отменить.
        for record in records.values where grouped[record.importedAt] == nil && !record.modifications.isEmpty {
            batches.append(ImportBatch(
                importedAt: record.importedAt,
                fileName: record.fileName,
                transactionCount: 0,
                firstDate: nil,
                lastDate: nil,
                record: record
            ))
        }

        return batches.sorted { $0.importedAt > $1.importedAt }
    }

    // MARK: - Undo

    /// Отменяет импорт: удаляет добавленные им операции, возвращает прежние значения
    /// поправленных (если их не меняли после), возвращает удалённые сразу после импорта
    /// дубли и удаляет созданные импортом счета, если они больше не нужны.
    static func undo(importedAt: Date, context: ModelContext) throws -> ImportUndoSummary {
        var summary = ImportUndoSummary()
        let record = loadRecords().first { $0.importedAt == importedAt }

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let accountsByKey = Dictionary(accounts.map { (key(of: $0), $0) }, uniquingKeysWith: { first, _ in first })

        let imported = transactions.filter { $0.importedAt == importedAt }
        let importedIDs = Set(imported.map(\.persistentModelID))
        let remaining = transactions.filter { !importedIDs.contains($0.persistentModelID) }

        for transaction in imported {
            context.delete(transaction)
        }
        summary.deletedCount = imported.count

        var restoredEntries: [RemovedDuplicate] = []

        if let record {
            // Точные копии (бэкап поверх данных) дают одинаковый ключ — берём ту,
            // что ещё в состоянии «после импорта».
            let byKey = Dictionary(grouping: remaining, by: { key(of: $0) })

            for modification in record.modifications {
                guard let candidates = byKey[modification.transactionKey] else { continue }

                if let transaction = candidates.first(where: { TransactionFieldValues($0) == modification.after }) {
                    modification.before.apply(to: transaction, accountsByKey: accountsByKey)
                    summary.revertedCount += 1
                } else {
                    summary.skippedChangedCount += 1
                }
            }

            // Дубли, которые автоочистка убрала из-за этого импорта. Копии из самого
            // отменяемого импорта не возвращаем — он же удаляется.
            let removedIDs = Set(record.removedDuplicateIDs)
            restoredEntries = DuplicateRemovalLog.load().filter {
                removedIDs.contains($0.id) && $0.importedAt != importedAt
            }
            for entry in restoredEntries {
                context.insert(entry.makeTransaction(accounts: accounts))
            }
            summary.restoredDuplicatesCount = restoredEntries.count

            let stillUsed = Set(
                remaining
                    .flatMap { [$0.fromAccount, $0.toAccount] }
                    .compactMap { $0.map(key(of:)) }
            )
            for accountKey in record.createdAccountKeys where !stillUsed.contains(accountKey) {
                if let account = accountsByKey[accountKey] {
                    context.delete(account)
                }
            }
        }

        try context.save()

        removeRecord(importedAt: importedAt)
        DuplicateRemovalLog.remove(restoredEntries)

        return summary
    }
}
