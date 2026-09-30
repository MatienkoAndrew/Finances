import Foundation
import Testing
@testable import Finances

@MainActor
@Suite("Сопоставление выписки с базой и поиск дублей")
struct DeduplicationTests {
    private func snapshot(
        _ date: Date,
        _ amount: Double,
        _ details: String,
        fx: (Double, String)? = nil,
        direction: Int = -1,
        imported: Bool = true
    ) -> TransactionSnapshot {
        TransactionSnapshot(
            date: date,
            details: details,
            amount: amount,
            currencyCode: "KZT",
            foreignAmount: fx?.0,
            foreignCurrencyCode: fx?.1,
            direction: direction,
            wasImported: imported
        )
    }

    // MARK: - StatementDeduplicator

    @Test("Повторный импорт той же выписки ничего не добавляет")
    func sameStatementTwice() {
        var fixture = StatementFixture(from: "01.03.26", to: "19.03.26")
        fixture.purchase("10.03.26", 500, "COFFEE BOOM")
        fixture.purchase("10.03.26", 500, "COFFEE BOOM")
        fixture.purchase("11.03.26", 2317.19, "VNPAY XLIII COFFEE", fx: (125_000, "VND"))
        let rows = fixture.statement.rows

        let existing = rows.map { row in
            snapshot(row.date, abs(row.amount), row.details, fx: row.foreignAmount.map { (abs($0), row.foreignCurrency ?? "") })
        }
        let result = StatementDeduplicator.match(rows: rows, existing: existing)
        #expect(result.unmatchedRowIndices.isEmpty)
        #expect(result.matches.count == 3)
    }

    @Test("Одинаковые покупки в один день — разные операции: 4 в выписке, 1 в базе → 3 новых")
    func sameDayIdenticalPurchases() {
        var fixture = StatementFixture(from: "20.09.26", to: "29.09.26")
        for _ in 0..<4 { fixture.purchase("25.09.26", 2295.32, "ZIGJAEG", fx: (7000, "KRW")) }
        let rows = fixture.statement.rows

        let existing = [snapshot(kaspiDay("25.09.26"), 2295.32, "ZIGJAEG", fx: (7000, "KRW"))]
        let result = StatementDeduplicator.match(rows: rows, existing: existing)
        #expect(result.matches.count == 1)
        #expect(result.unmatchedRowIndices.count == 3)
    }

    @Test("Предварительная сумма в тенге → окончательная: та же операция по сумме в валюте")
    func pendingAmountMatchesByForeignAmount() {
        var fixture = StatementFixture(from: "28.02.26", to: "30.03.26")
        fixture.purchase("17.03.26", 63431.07, "AGODA.COM LUK INN HO", fx: (3_428_444, "VND"))
        let rows = fixture.statement.rows

        let existing = [snapshot(kaspiDay("17.03.26"), 64681.66, "AGODA.COM LUK INN HO", fx: (3_428_444, "VND"))]
        let result = StatementDeduplicator.match(rows: rows, existing: existing)
        #expect(result.matches.count == 1)
        #expect(result.unmatchedRowIndices.isEmpty)
    }

    @Test("Соседние выписки без перекрытия: проезд в первый день не съедается проездом в последний")
    func adjacentStatementsKeepBoundaryPurchase() {
        var fixture = StatementFixture(from: "30.09.26", to: "15.10.26")
        fixture.purchase("30.09.26", 200, "ONAY.KZ")
        let rows = fixture.statement.rows

        let existing = [snapshot(kaspiDay("29.09.26"), 200, "ONAY.KZ")]
        let result = StatementDeduplicator.match(rows: rows, existing: existing)
        #expect(result.matches.isEmpty)
        #expect(result.unmatchedRowIndices == [0])
    }

    @Test("Старый импорт в другом поясе и без пунктуации в описании — та же операция", arguments: [
        "Asia/Seoul", "Europe/Moscow", "Asia/Ho_Chi_Minh", "Asia/Almaty", "Europe/Berlin"
    ])
    func legacyImportFromOtherTimeZone(zone: String) {
        var fixture = StatementFixture(from: "01.09.26", to: "29.09.26")
        fixture.purchase("24.09.26", 727.34, "7-ELEVEN", fx: (2200, "KRW"))
        fixture.purchase("25.09.26", 727.34, "7-ELEVEN", fx: (2200, "KRW"))
        let rows = fixture.statement.rows

        let timeZone = TimeZone(identifier: zone)!
        let existing = [
            snapshot(legacyMidnight("24.09.26", in: timeZone), 727.34, "7 ELEVEN", fx: (2200, "KRW")),
            snapshot(legacyMidnight("25.09.26", in: timeZone), 727.34, "7 ELEVEN", fx: (2200, "KRW"))
        ]
        let result = StatementDeduplicator.match(rows: rows, existing: existing)
        #expect(result.unmatchedRowIndices.isEmpty)
        // Каждая строка сопоставлена с операцией своего дня, а не соседнего.
        for match in result.matches {
            #expect(
                StatementDeduplicator.dayNumber(of: existing[match.existingIndex])
                    == StatementDeduplicator.dayNumber(of: snapshot(rows[match.rowIndex].date, 0, ""))
            )
        }
    }

    @Test("Fingerprint новых строк не совпадает с уже занятыми")
    func fingerprintsAvoidUsed() {
        var fixture = StatementFixture(from: "20.09.26", to: "29.09.26")
        fixture.purchase("25.09.26", 500, "COFFEE")
        fixture.purchase("25.09.26", 500, "COFFEE")
        let rows = fixture.statement.rows

        let first = StatementDeduplicator.fingerprints(for: rows, avoiding: [])
        #expect(Set(first).count == 2)

        let next = StatementDeduplicator.fingerprints(for: [rows[0]], avoiding: [first[0]])
        #expect(next[0] != first[0])
    }

    // MARK: - DuplicateDetector

    private func candidate(
        _ snapshot: TransactionSnapshot,
        batch: Date?,
        fingerprint: String? = UUID().uuidString,
        createdAt: Date? = nil,
        hasAccount: Bool = true
    ) -> DuplicateCandidate {
        DuplicateCandidate(
            snapshot: snapshot,
            fingerprint: fingerprint,
            createdAt: createdAt ?? batch ?? Date(),
            importedAt: batch,
            hasAccount: hasAccount
        )
    }

    @Test("Старый дубль: одна валютная покупка из двух импортов с разной суммой в тенге; оставляем окончательную")
    func legacyPendingDuplicate() {
        let olderStatement = Date(timeIntervalSince1970: 1_000)   // выписка до 19.03 — предварительная сумма
        let newerStatement = Date(timeIntervalSince1970: 500)     // выписка до 30.03, импортирована раньше
        let items = [
            candidate(snapshot(kaspiDay("19.03.26"), 2317.19, "MPOS*4BMART", fx: (125_000, "VND")), batch: olderStatement),
            candidate(snapshot(kaspiDay("30.03.26"), 500, "GOOD MART"), batch: newerStatement),
            candidate(snapshot(kaspiDay("19.03.26"), 2312.87, "MPOS*4BMART", fx: (125_000, "VND")), batch: newerStatement)
        ]

        let groups = DuplicateDetector.findGroups(in: items)
        #expect(groups.count == 1)
        #expect(groups[0].reason == .repeatedImport)
        #expect(groups[0].memberIndices == [0, 2])
        #expect(groups[0].keepIndex == 2, "оставляем копию из выписки, которая кончается позже")
    }

    @Test("Дозагрузка потерянной покупки с той же суммой — не дубль")
    func deltaReimportIsNotDuplicate() {
        let items = [
            candidate(snapshot(kaspiDay("24.01.26"), 2305.95, "WWA PORTAL", fx: (140, "THB")), batch: Date(timeIntervalSince1970: 1)),
            candidate(snapshot(kaspiDay("24.01.26"), 2305.95, "WWA PORTAL", fx: (140, "THB")), batch: Date(timeIntervalSince1970: 2))
        ]
        #expect(DuplicateDetector.findGroups(in: items).isEmpty)
    }

    @Test("Точные копии из бэкапа: оставляем привязанную к счёту")
    func exactCopies() {
        let batch = Date(timeIntervalSince1970: 1)
        let original = snapshot(kaspiDay("10.03.26"), 500, "COFFEE")
        let items = [
            candidate(original, batch: batch, fingerprint: "fp-1", hasAccount: false),
            candidate(original, batch: batch, fingerprint: "fp-1", hasAccount: true)
        ]
        let groups = DuplicateDetector.findGroups(in: items)
        #expect(groups.count == 1)
        #expect(groups[0].reason == .exactCopy)
        #expect(groups[0].keepIndex == 1)
    }

    @Test("Две ручные покупки кофе в один день — не дубли")
    func manualSameDayPurchases() {
        let day = kaspiDay("10.03.26")
        let items = [
            candidate(snapshot(day, 500, "Кофе", imported: false), batch: nil, fingerprint: nil, createdAt: day),
            candidate(snapshot(day, 500, "Кофе", imported: false), batch: nil, fingerprint: nil, createdAt: day.addingTimeInterval(3600))
        ]
        #expect(DuplicateDetector.findGroups(in: items).isEmpty)
    }
}
