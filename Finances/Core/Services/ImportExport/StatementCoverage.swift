//
//  StatementCoverage.swift
//  Finances
//
//  Какие дни покрыты импортированными выписками Kaspi и сошлись ли их итоги —
//  для статуса сверки в сводке месяца.
//

import Foundation

/// Одна импортированная выписка: её период и результат проверки итогов.
struct StatementCoverage: Codable, Identifiable {
    var id: Date { importedAt }

    let importedAt: Date
    let fileName: String
    let periodStart: Date
    let periodEnd: Date
    /// Типы операций, по которым сумма строк не сошлась с итогом выписки.
    let mismatchedTypes: [String]
    let unrecognizedLinesCount: Int

    var isConsistent: Bool {
        mismatchedTypes.isEmpty && unrecognizedLinesCount == 0
    }

    init?(statement: KaspiStatement, fileName: String, importedAt: Date) {
        let dates = statement.rows.map(\.date)
        guard let start = statement.periodStart ?? dates.min(),
              let end = statement.periodEnd ?? dates.max() else { return nil }
        self.importedAt = importedAt
        self.fileName = fileName
        periodStart = start
        periodEnd = end
        mismatchedTypes = statement.mismatchedTypes.map(\.summaryTitle)
        unrecognizedLinesCount = statement.unrecognizedLines.count
    }

    init(importedAt: Date, fileName: String, periodStart: Date, periodEnd: Date) {
        self.importedAt = importedAt
        self.fileName = fileName
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        mismatchedTypes = []
        unrecognizedLinesCount = 0
    }
}

@MainActor
enum StatementCoverageStore {
    private static let limit = 200

    private static var fileURL: URL {
        ImportStorage.fileURL("statement-coverage.json")
    }

    private static var cache: (url: URL, items: [StatementCoverage])?

    static func load() -> [StatementCoverage] {
        let url = fileURL
        if let cache, cache.url == url { return cache.items }
        let items = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([StatementCoverage].self, from: $0) } ?? []
        cache = (url, items)
        return items
    }

    static func add(_ coverage: StatementCoverage) {
        save(Array(([coverage] + load().filter { $0.importedAt != coverage.importedAt }).prefix(limit)))
    }

    static func remove(importedAt: Date) {
        let items = load()
        guard items.contains(where: { $0.importedAt == importedAt }) else { return }
        save(items.filter { $0.importedAt != importedAt })
    }

    private static func save(_ items: [StatementCoverage]) {
        cache = (fileURL, items)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Насколько полные данные: по какой день сверена Kaspi, где нет выписки,
/// какие выписки не сошлись и сколько оплат Apple Pay ждут выписку.
struct ReconciliationStatus {
    struct Gap: Identifiable {
        var id: Date { start }
        /// Первый день без выписки.
        let start: Date
        /// Последний день без выписки (включительно).
        let end: Date
    }

    /// Последний день, покрытый выпиской без разрывов до него; nil — выписок не было.
    let coveredThrough: Date?
    /// Дни без выписки между первой выпиской и последним покрытым днём.
    let gaps: [Gap]
    /// Выписки, итоги которых не сошлись с прочитанными строками.
    let inconsistentStatements: [StatementCoverage]
    /// Оплаты Apple Pay, которых ещё нет в выписке.
    let awaitingStatement: [Transaction]
    /// Операции, ждущие решения по метке.
    let pendingTags: [Transaction]

    var needsAttention: Bool {
        !gaps.isEmpty || !inconsistentStatements.isEmpty || !awaitingStatement.isEmpty || !pendingTags.isEmpty
    }

    /// Не покрыт ли выпиской какой-то день периода (до сегодня).
    func isFullyCovered(start: Date, endExclusive: Date, now: Date = .now) -> Bool {
        let calendar = KaspiStatementParser.calendar
        guard let coveredThrough else { return false }
        let lastNeeded = calendar.startOfDay(for: min(calendar.date(byAdding: .second, value: -1, to: endExclusive) ?? endExclusive, now))
        guard calendar.startOfDay(for: coveredThrough) >= lastNeeded else { return false }
        return !gaps.contains { $0.end >= start && $0.start < endExclusive }
    }

    static func make(
        coverages: [StatementCoverage],
        legacyBatches: [ImportBatch],
        transactions: [Transaction]
    ) -> ReconciliationStatus {
        let calendar = KaspiStatementParser.calendar
        let known = Set(coverages.map(\.importedAt))
        // Импорты до появления учёта периода — по датам их операций.
        let legacy = legacyBatches.compactMap { batch -> StatementCoverage? in
            guard !known.contains(batch.importedAt), let first = batch.firstDate, let last = batch.lastDate else { return nil }
            return StatementCoverage(importedAt: batch.importedAt, fileName: batch.fileName ?? "", periodStart: first, periodEnd: last)
        }

        // Дни как полуинтервалы [начало, конец) по времени Kaspi; соседние склеиваются.
        let intervals = (coverages + legacy)
            .map { coverage -> (Date, Date) in
                let start = calendar.startOfDay(for: coverage.periodStart)
                let lastDay = calendar.startOfDay(for: coverage.periodEnd)
                return (start, calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay)
            }
            .sorted { $0.0 < $1.0 }

        var merged: [(start: Date, end: Date)] = []
        for (start, end) in intervals {
            if let last = merged.last, start <= last.end {
                merged[merged.count - 1].end = max(last.end, end)
            } else {
                merged.append((start, end))
            }
        }

        // Дни хранятся полуднем по времени Kaspi, как даты операций: так подпись
        // не съезжает на соседний день в другом часовом поясе.
        func noon(_ day: Date) -> Date {
            calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        }

        var gaps: [Gap] = []
        for (previous, next) in zip(merged, merged.dropFirst()) {
            let lastMissing = calendar.date(byAdding: .day, value: -1, to: next.start) ?? next.start
            gaps.append(Gap(start: noon(previous.end), end: noon(lastMissing)))
        }

        let coveredThrough = merged.last.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) }.map(noon)

        return ReconciliationStatus(
            coveredThrough: coveredThrough,
            gaps: gaps.reversed(),
            inconsistentStatements: coverages.filter { !$0.isConsistent },
            awaitingStatement: transactions.filter(\.isAwaitingStatement).sorted { $0.date > $1.date },
            pendingTags: transactions.filter { !($0.pendingTagNames ?? []).isEmpty }.sorted { $0.date > $1.date }
        )
    }
}

@MainActor
extension ReconciliationStatus {
    private static var cache: (key: [Int], status: ReconciliationStatus)?

    /// Статус, посчитанный один раз, пока операции и выписки не поменялись.
    ///
    /// Экраны перерисовываются часто (смена масштаба аналитики — дважды подряд),
    /// а статус группирует все операции по импортам. Ключ — ревизия операций
    /// (растёт при любом их сохранении) и число выписок и импортов.
    static func cached(_ snapshot: AllTransactionsSnapshot) -> ReconciliationStatus {
        let coverages = StatementCoverageStore.load()
        let key = [snapshot.revision, snapshot.items.count, coverages.count, ImportHistory.loadRecords().count]
        if let cache, cache.key == key { return cache.status }

        let status = make(
            coverages: coverages,
            legacyBatches: ImportHistory.batches(in: snapshot.items),
            transactions: snapshot.items
        )
        cache = (key, status)
        return status
    }
}
