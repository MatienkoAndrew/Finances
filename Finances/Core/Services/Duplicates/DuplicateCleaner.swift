import Foundation
import SwiftData

/// Группа дублей из базы (см. `DuplicateDetector`).
struct StoredDuplicateGroup: Identifiable {
    /// Подпись группы — стабильна, пока состав группы не меняется.
    let id: String
    let reason: DuplicateGroup.Reason
    let members: [Transaction]
    let suggestedKeep: PersistentIdentifier
}

/// Поиск, удаление и автоматическая очистка дублей.
///
/// Всё удалённое попадает в `DuplicateRemovalLog` и может быть восстановлено.
/// Восстановленные операции и группы, отмеченные «Не дубль», больше не считаются дублями.
@MainActor
enum DuplicateCleaner {
    static let autoCleanupKey = "duplicates_auto_cleanup"
    private static let exemptKey = "duplicates_exempt_transactions"

    /// По умолчанию включено.
    static var isAutoCleanupEnabled: Bool {
        ImportStorage.defaults.object(forKey: autoCleanupKey) as? Bool ?? true
    }

    // MARK: - Finding

    static func findGroups(in transactions: [Transaction], accounts: [Account]) -> [StoredDuplicateGroup] {
        let exempt = exemptIdentities
        let candidates = transactions.filter { !exempt.contains(identity(of: $0)) }
        let kaspiAccount = AccountLookup.kaspi(in: accounts)

        let items = candidates.map { transaction in
            DuplicateCandidate(
                snapshot: PDFImporter.snapshot(of: transaction, kaspiAccount: kaspiAccount),
                fingerprint: transaction.fingerprint,
                createdAt: transaction.createdAt,
                importedAt: transaction.importedAt,
                hasAccount: transaction.fromAccount != nil || transaction.toAccount != nil
            )
        }

        return DuplicateDetector.findGroups(in: items).map { found in
            let members = found.memberIndices.map { candidates[$0] }
            return StoredDuplicateGroup(
                id: members.map(identity(of:)).sorted().joined(separator: ";"),
                reason: found.reason,
                members: members,
                suggestedKeep: candidates[found.keepIndex].persistentModelID
            )
        }
    }

    // MARK: - Removing

    /// Удаляет из каждой группы всё, кроме оставляемой операции, и переносит в неё
    /// метки, заметку и ручную категорию. Контекст не сохраняет.
    @discardableResult
    static func removeExtras(
        in groups: [StoredDuplicateGroup],
        keeping keepSelection: [String: PersistentIdentifier] = [:],
        automatic: Bool,
        context: ModelContext
    ) -> [RemovedDuplicate] {
        var removed: [RemovedDuplicate] = []
        let removedAt = Date()

        for group in groups {
            let keepID = keepSelection[group.id] ?? group.suggestedKeep
            guard let keep = group.members.first(where: { $0.persistentModelID == keepID }) else { continue }

            for duplicate in group.members where duplicate.persistentModelID != keepID {
                removed.append(RemovedDuplicate(duplicate, keptDetails: keep.details, removedAt: removedAt, automatic: automatic))
                mergeUserData(from: duplicate, into: keep)
                context.delete(duplicate)
            }
        }

        DuplicateRemovalLog.append(removed)
        return removed
    }

    /// Автоочистка после импорта. Вызывать после вставки новых операций;
    /// контекст сохраняет сама. Возвращает удалённые дубли.
    @discardableResult
    static func autoCleanupIfEnabled(context: ModelContext) -> [RemovedDuplicate] {
        guard isAutoCleanupEnabled else { return [] }

        let transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let groups = findGroups(in: transactions, accounts: accounts)
        guard !groups.isEmpty else { return [] }

        let removed = removeExtras(in: groups, automatic: true, context: context)

        do {
            try context.save()
        } catch {
            context.rollback()
            DuplicateRemovalLog.remove(removed)
            return []
        }

        return removed
    }

    // MARK: - Exempting and restoring

    /// Операции группы больше не считаются дублями.
    static func markNotDuplicate(_ group: StoredDuplicateGroup) {
        exemptIdentities.formUnion(group.members.map(identity(of:)))
    }

    /// Возвращает удалённую операцию в базу и больше не считает её дублем.
    static func restore(_ entry: RemovedDuplicate, accounts: [Account], context: ModelContext) throws {
        let transaction = entry.makeTransaction(accounts: accounts)
        context.insert(transaction)
        try context.save()

        exemptIdentities.insert(identity(of: transaction))
        DuplicateRemovalLog.remove([entry])
    }

    private static var exemptIdentities: Set<String> {
        get { Set(ImportStorage.defaults.stringArray(forKey: exemptKey) ?? []) }
        set { ImportStorage.defaults.set(newValue.sorted(), forKey: exemptKey) }
    }

    /// Точные копии дают одинаковую подпись — «Не дубль» и восстановление относятся к обеим.
    private static func identity(of transaction: Transaction) -> String {
        [
            transaction.fingerprint ?? "-",
            "\(transaction.createdAt.timeIntervalSinceReferenceDate)",
            "\(transaction.date.timeIntervalSinceReferenceDate)",
            transaction.details
        ].joined(separator: "|")
    }

    private static func mergeUserData(from duplicate: Transaction, into keep: Transaction) {
        let keepTags = keep.tagNames ?? []
        let tags = keepTags + (duplicate.tagNames ?? []).filter { !keepTags.contains($0) }
        if !tags.isEmpty {
            keep.tagNames = tags
        }

        if (keep.note ?? "").isEmpty, let note = duplicate.note, !note.isEmpty {
            keep.note = note
        }

        let duplicateHasManualCategory = duplicate.isCategoryManuallySet == true && duplicate.categoryName != nil
        if (duplicateHasManualCategory && keep.isCategoryManuallySet != true)
            || (keep.categoryName == nil && duplicate.categoryName != nil) {
            keep.categoryName = duplicate.categoryName
            keep.subcategoryName = duplicate.subcategoryName
            keep.isCategoryManuallySet = duplicate.isCategoryManuallySet
        }
    }
}

// MARK: - Removal log

/// Удалённый дубль со всеми полями — чтобы его можно было восстановить.
struct RemovedDuplicate: Codable, Identifiable, Equatable {
    let id: UUID
    let removedAt: Date
    let automatic: Bool
    /// Описание оставленной операции — чтобы показать, с чем склеили.
    let keptDetails: String

    let date: Date
    let kindRaw: String
    let amount: Double
    let currencyCode: String
    let toAmount: Double?
    let toCurrencyCode: String?
    let details: String
    let foreignAmount: Double?
    let foreignCurrencyCode: String?
    let rubAmount: Double?
    let categoryName: String?
    let subcategoryName: String?
    let isCategoryManuallySet: Bool?
    let note: String?
    let tagNames: [String]?
    let manuallyExcludedTagNames: [String]?
    let fingerprint: String?
    let sourceFileName: String?
    let importedAt: Date?
    /// Optional — старые записи журнала декодируются.
    let walletMerchant: String?
    let createdAt: Date
    let fromAccountName: String?
    let toAccountName: String?

    init(_ transaction: Transaction, keptDetails: String, removedAt: Date, automatic: Bool) {
        id = UUID()
        self.removedAt = removedAt
        self.automatic = automatic
        self.keptDetails = keptDetails
        date = transaction.date
        kindRaw = transaction.kindRaw
        amount = transaction.amount
        currencyCode = transaction.currencyCode
        toAmount = transaction.toAmount
        toCurrencyCode = transaction.toCurrencyCode
        details = transaction.details
        foreignAmount = transaction.foreignAmount
        foreignCurrencyCode = transaction.foreignCurrencyCode
        rubAmount = transaction.rubAmount
        categoryName = transaction.categoryName
        subcategoryName = transaction.subcategoryName
        isCategoryManuallySet = transaction.isCategoryManuallySet
        note = transaction.note
        tagNames = transaction.tagNames
        manuallyExcludedTagNames = transaction.manuallyExcludedTagNames
        fingerprint = transaction.fingerprint
        sourceFileName = transaction.sourceFileName
        importedAt = transaction.importedAt
        walletMerchant = transaction.walletMerchant
        createdAt = transaction.createdAt
        fromAccountName = transaction.fromAccount?.name
        toAccountName = transaction.toAccount?.name
    }

    func makeTransaction(accounts: [Account]) -> Transaction {
        func account(named name: String?) -> Account? {
            guard let name else { return nil }
            return accounts.first { $0.name == name && !$0.isArchived } ?? accounts.first { $0.name == name }
        }

        return Transaction(
            date: date,
            kindRaw: kindRaw,
            amount: amount,
            currencyCode: currencyCode,
            toAmount: toAmount,
            toCurrencyCode: toCurrencyCode,
            details: details,
            foreignAmount: foreignAmount,
            foreignCurrencyCode: foreignCurrencyCode,
            rubAmount: rubAmount,
            categoryName: categoryName,
            subcategoryName: subcategoryName,
            isCategoryManuallySet: isCategoryManuallySet,
            note: note,
            tagNames: tagNames,
            manuallyExcludedTagNames: manuallyExcludedTagNames,
            fingerprint: fingerprint,
            sourceFileName: sourceFileName,
            importedAt: importedAt,
            walletMerchant: walletMerchant,
            createdAt: createdAt,
            fromAccount: account(named: fromAccountName),
            toAccount: account(named: toAccountName)
        )
    }
}

/// Журнал удалённых дублей — JSON-файл в Application Support, последние `limit` записей.
@MainActor
enum DuplicateRemovalLog {
    private static let limit = 500

    private static var fileURL: URL {
        ImportStorage.fileURL("removed-duplicates.json")
    }

    /// Новые сверху.
    static func load() -> [RemovedDuplicate] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        // Формат дат по умолчанию (секунды с долями): по датам определяется
        // идентичность операции, ISO 8601 потерял бы доли секунды.
        return (try? JSONDecoder().decode([RemovedDuplicate].self, from: data)) ?? []
    }

    static func append(_ entries: [RemovedDuplicate]) {
        guard !entries.isEmpty else { return }
        save(Array((entries + load()).prefix(limit)))
    }

    static func remove(_ entries: [RemovedDuplicate]) {
        guard !entries.isEmpty else { return }
        let ids = Set(entries.map(\.id))
        save(load().filter { !ids.contains($0.id) })
    }

    private static func save(_ entries: [RemovedDuplicate]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
