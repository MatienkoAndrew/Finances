import Foundation

/// Транзакция-кандидат для поиска дублей — без SwiftData, чтобы логику можно было проверять отдельно.
struct DuplicateCandidate {
    let snapshot: TransactionSnapshot
    let fingerprint: String?
    let createdAt: Date
    /// Все операции одного импорта PDF имеют одинаковое значение — это «пакет».
    let importedAt: Date?
    /// Привязана к счёту. Копии из бэкапа теряют привязку, поэтому оставлять их хуже.
    let hasAccount: Bool
}

struct DuplicateGroup {
    enum Reason {
        /// Одна и та же запись несколько раз (например, бэкап импортирован поверх данных).
        case exactCopy
        /// Одна и та же операция пришла из разных импортов выписок.
        case repeatedImport
    }

    let reason: Reason
    /// Какую транзакцию предлагается оставить (индекс во входном массиве).
    let keepIndex: Int
    /// Все транзакции группы, включая `keepIndex`, в порядке входного массива.
    let memberIndices: [Int]
}

/// Ищет уже сохранённые дубли.
///
/// 1. Точные копии: одинаковый fingerprint, а у ручных операций — одинаковые
///    `createdAt`, дата, описание и сумма. Так выглядят записи, задвоенные бэкапом.
/// 2. Повторные импорты: импорты сравниваются между собой так же, как новая выписка
///    с базой (`StatementDeduplicator`). Внутри одного импорта одинаковые операции —
///    это разные покупки, между импортами — одна и та же. Так находятся дубли
///    из-за предварительной суммы в тенге (старый импорт считал их разными).
///
/// Ручные операции со вторым шагом не сравниваются: у них другое описание,
/// и совпадение по сумме и дню слишком часто было бы ложным.
enum DuplicateDetector {
    static func findGroups(in items: [DuplicateCandidate], calendar: Calendar = .current) -> [DuplicateGroup] {
        var links = UnionFind(count: items.count)
        var repeatedImportRoots = Set<Int>()

        // Самая поздняя операция в каждом импорте — оценка конца периода его выписки.
        var batchEnds: [Date: Date] = [:]
        for item in items {
            guard let importedAt = item.importedAt else { continue }
            batchEnds[importedAt] = max(batchEnds[importedAt] ?? .distantPast, item.snapshot.date)
        }

        func isBetterToKeep(_ lhs: Int, than rhs: Int) -> Bool {
            DuplicateDetector.isBetterToKeep(lhs, than: rhs, in: items, batchEnds: batchEnds)
        }

        // 1. Точные копии.
        let exactKeyed = items.indices.map { index in (index, exactCopyKey(items[index])) }
        for (_, indices) in Dictionary(grouping: exactKeyed, by: \.1) where indices.count > 1 {
            for (index, _) in indices.dropFirst() {
                links.union(indices[0].0, index)
            }
        }

        // От каждой группы точных копий дальше участвует один представитель.
        var representatives: [Int: Int] = [:]
        for index in items.indices {
            let root = links.find(index)
            if let current = representatives[root] {
                if isBetterToKeep(index, than: current) { representatives[root] = index }
            } else {
                representatives[root] = index
            }
        }

        // 2. Повторные импорты: от новых импортов к старым, каждый пакет
        //    сравнивается со всем, что уже набрано из более новых.
        let batches = Dictionary(
            grouping: representatives.values.filter { items[$0].importedAt != nil },
            by: { items[$0].importedAt! }
        )
        .sorted { $0.key > $1.key }
        .map { $0.value.sorted() }

        var kept: [Int] = []

        for batch in batches {
            let result = StatementDeduplicator.match(
                batch.map { items[$0].snapshot },
                against: kept.map { items[$0].snapshot },
                matchRenamed: false,
                calendar: calendar
            )

            for match in result.matches {
                links.union(kept[match.existingIndex], batch[match.rowIndex])
                repeatedImportRoots.insert(kept[match.existingIndex])
            }

            kept.append(contentsOf: result.unmatchedRowIndices.map { batch[$0] })
        }

        let rootsWithRepeatedImport = Set(repeatedImportRoots.map { links.find($0) })

        return Dictionary(grouping: items.indices, by: { links.find($0) })
            .values
            .filter { $0.count > 1 }
            .map { members in
                let sorted = members.sorted()
                let keep = sorted.dropFirst().reduce(sorted[0]) { best, index in
                    isBetterToKeep(index, than: best) ? index : best
                }
                return DuplicateGroup(
                    reason: rootsWithRepeatedImport.contains(links.find(keep)) ? .repeatedImport : .exactCopy,
                    keepIndex: keep,
                    memberIndices: sorted
                )
            }
            .sorted { items[$0.keepIndex].snapshot.date > items[$1.keepIndex].snapshot.date }
    }

    private static func exactCopyKey(_ item: DuplicateCandidate) -> String {
        if let fingerprint = item.fingerprint, !fingerprint.isEmpty {
            return "fp|\(fingerprint)"
        }

        let snapshot = item.snapshot
        return [
            "raw",
            "\(item.createdAt.timeIntervalSinceReferenceDate)",
            "\(snapshot.date.timeIntervalSinceReferenceDate)",
            snapshot.details,
            "\(snapshot.direction)",
            "\(Int((snapshot.amount * 100).rounded()))",
            snapshot.currencyCode
        ].joined(separator: "|")
    }

    /// Оставлять лучше привязанную к счёту, затем из выписки, которая заканчивается позже
    /// (там сумма в тенге окончательная, а не предварительная; порядок импорта тут
    /// не показатель — старую выписку могли импортировать после новой), затем из
    /// более нового импорта, затем ту, что раньше в списке.
    private static func isBetterToKeep(
        _ lhs: Int,
        than rhs: Int,
        in items: [DuplicateCandidate],
        batchEnds: [Date: Date]
    ) -> Bool {
        let left = items[lhs]
        let right = items[rhs]

        if left.hasAccount != right.hasAccount {
            return left.hasAccount
        }

        let leftEnd = left.importedAt.flatMap { batchEnds[$0] } ?? .distantPast
        let rightEnd = right.importedAt.flatMap { batchEnds[$0] } ?? .distantPast
        if leftEnd != rightEnd {
            return leftEnd > rightEnd
        }

        let leftImported = left.importedAt ?? .distantPast
        let rightImported = right.importedAt ?? .distantPast
        if leftImported != rightImported {
            return leftImported > rightImported
        }

        return lhs < rhs
    }
}

private struct UnionFind {
    private var parent: [Int]

    init(count: Int) {
        parent = Array(0..<count)
    }

    mutating func find(_ index: Int) -> Int {
        var root = index
        while parent[root] != root { root = parent[root] }

        var current = index
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }

        return root
    }

    mutating func union(_ lhs: Int, _ rhs: Int) {
        let leftRoot = find(lhs)
        let rightRoot = find(rhs)
        if leftRoot != rightRoot { parent[rightRoot] = leftRoot }
    }
}
