import Foundation
import SwiftData
import Testing
@testable import Finances

@MainActor
@Suite("Импорт, отмена, аналитика и сверка баланса", .serialized)
struct ImportFlowTests {
    // MARK: - Импорт

    @Test("Виды операций: покупка, курсовая разница, возврат, пополнение, снятие наличных")
    func importCreatesRightKinds() throws {
        let env = try ImportTestEnvironment()
        var fixture = StatementFixture(from: "01.12.25", to: "08.12.25")
        fixture.purchase("08.12.25", 5821.67, "HANGTIME HOSTEL (PVT) LTD", fx: (3509, "LKR"))
        fixture.exchangeRateDifference("07.12.25", 4.57, "HANGTIME HOSTEL (PVT) LTD")
        fixture.row("06.12.25", 1098, .purchase, "Jet Sharing Powerbank")
        fixture.row("05.12.25", 50_000, .topUp, "С карты другого банка")
        fixture.row("04.12.25", -20_000, .withdrawal, "Банкомат SBK MRS", fx: (-11_500, "LKR"))

        let result = try env.importStatement(fixture)
        #expect(result.transactions.count == 5)
        #expect(result.accountsToCreate.map(\.name) == ["Cash LKR"])

        let byDetails = Dictionary(grouping: env.transactions, by: \.details)
        let purchase = try #require(byDetails["HANGTIME HOSTEL (PVT) LTD"]?.first { $0.kind == .expense })
        #expect(purchase.amount == 5821.67 && purchase.foreignAmount == 3509 && purchase.fromAccount?.name == "Kaspi")

        let difference = try #require(byDetails["HANGTIME HOSTEL (PVT) LTD"]?.first { $0.kind == .income })
        #expect(difference.isExchangeRateDifference && difference.toAccount?.name == "Kaspi")

        let refund = try #require(byDetails["Jet Sharing Powerbank"]?.first)
        #expect(refund.kind == .income)

        let withdrawal = try #require(byDetails["Банкомат SBK MRS"]?.first)
        #expect(withdrawal.kind == .transfer && withdrawal.toAccount?.name == "Cash LKR" && withdrawal.toAmount == 11_500)
    }

    @Test("Повторный импорт той же выписки: «уже импортированы»")
    func reimportThrows() throws {
        let env = try ImportTestEnvironment()
        var fixture = StatementFixture(from: "01.03.26", to: "19.03.26")
        fixture.purchase("10.03.26", 500, "COFFEE BOOM")
        try env.importStatement(fixture)

        #expect(throws: PDFImporterError.self) {
            try env.importStatement(fixture)
        }
        #expect(env.transactions.count == 1)
    }

    // MARK: - Уточнение сумм и отмена

    private var pendingStatement: StatementFixture {
        var fixture = StatementFixture(from: "01.03.26", to: "19.03.26")
        fixture.purchase("17.03.26", 64681.66, "AGODA.COM LUK INN HO", fx: (3_428_444, "VND"))
        fixture.purchase("10.03.26", 500, "COFFEE BOOM")
        return fixture
    }

    private var settledStatement: StatementFixture {
        var fixture = StatementFixture(from: "10.03.26", to: "30.03.26")
        fixture.purchase("25.03.26", 1200, "GOOD MART")
        fixture.purchase("17.03.26", 63431.07, "AGODA.COM LUK INN HO", fx: (3_428_444, "VND"))
        fixture.purchase("10.03.26", 500, "COFFEE BOOM")
        return fixture
    }

    @Test("Свежая выписка заменяет предварительную сумму окончательной, отмена возвращает прежнюю")
    func settleAndUndo() throws {
        let env = try ImportTestEnvironment()
        try env.importStatement(pendingStatement)
        let before = env.state

        let result = try env.importStatement(settledStatement)
        #expect(result.transactions.count == 1)
        #expect(result.settledAmountsCount == 1)

        let agoda = try #require(env.transactions.first { $0.details.hasPrefix("AGODA") })
        #expect(agoda.amount == 63431.07)

        let summary = try ImportHistory.undo(importedAt: result.importedAt, context: env.context)
        #expect(summary.deletedCount == 1 && summary.revertedCount == 1)
        #expect(agoda.amount == 64681.66)
        #expect(env.state == before)
        #expect(ImportHistory.loadRecords().count == 1, "осталась только запись первого импорта")
    }

    @Test("Старая выписка после новой не затирает окончательную сумму")
    func olderStatementDoesNotOverwrite() throws {
        let env = try ImportTestEnvironment()
        try env.importStatement(settledStatement)
        #expect(throws: PDFImporterError.self) {
            try env.importStatement(pendingStatement)
        }
        #expect(env.transactions.first { $0.details.hasPrefix("AGODA") }?.amount == 63431.07)
    }

    @Test("Старый импорт с неверным знаком: новый импорт исправляет, отмена возвращает как было")
    func legacyRepairAndUndo() throws {
        let env = try ImportTestEnvironment()
        let legacyBatch = Date(timeIntervalSince1970: 1_000_000)
        env.insertLegacy(date: legacyMidnight("29.09.26", in: TimeZone(identifier: "Asia/Seoul")!),
                         amount: 4.57, details: "GS25SEOKYOTEUNTEUNJUM", importedAt: legacyBatch)
        try env.context.save()
        let before = env.state

        var fixture = StatementFixture(from: "20.09.26", to: "29.09.26")
        fixture.exchangeRateDifference("29.09.26", 4.57, "GS25SEOKYOTEUNTEUNJUM")
        fixture.purchase("28.09.26", 3000, "CU SEOKYOBOSUKJUM")
        let result = try env.importStatement(fixture)
        #expect(result.transactions.count == 1)
        #expect(result.repairedCount == 1)

        let repaired = try #require(env.transactions.first { $0.details == "GS25SEOKYOTEUNTEUNJUM" })
        #expect(repaired.kind == .income && repaired.isExchangeRateDifference)
        #expect(repaired.categoryName == "Еда", "курсовая разница остаётся в категории покупки")

        let summary = try ImportHistory.undo(importedAt: result.importedAt, context: env.context)
        #expect(summary.revertedCount == 1)
        #expect(env.state == before)
    }

    @Test("Операцию изменили после импорта — отмена её не трогает")
    func undoSkipsEditedTransactions() throws {
        let env = try ImportTestEnvironment()
        try env.importStatement(pendingStatement)
        let result = try env.importStatement(settledStatement)

        let agoda = try #require(env.transactions.first { $0.details.hasPrefix("AGODA") })
        agoda.categoryName = "Путешествия"
        try env.context.save()

        let summary = try ImportHistory.undo(importedAt: result.importedAt, context: env.context)
        #expect(summary.skippedChangedCount == 1 && summary.revertedCount == 0)
        #expect(agoda.amount == 63431.07 && agoda.categoryName == "Путешествия")
    }

    @Test("Отмена удаляет созданный импортом счёт наличных")
    func undoDeletesCreatedAccount() throws {
        let env = try ImportTestEnvironment()
        var fixture = StatementFixture(from: "01.12.25", to: "08.12.25")
        fixture.row("04.12.25", -20_000, .withdrawal, "Банкомат SBK MRS", fx: (-11_500, "LKR"))
        let result = try env.importStatement(fixture)
        #expect(env.accounts.count == 2)

        _ = try ImportHistory.undo(importedAt: result.importedAt, context: env.context)
        #expect(env.accounts.map(\.name) == ["Kaspi"])
        #expect(env.transactions.isEmpty)
    }

    // MARK: - Автоочистка

    @Test("Автоочистка убирает старый дубль с предварительной суммой, отмена импорта возвращает его")
    func autoCleanupAndUndo() throws {
        let env = try ImportTestEnvironment()
        let day = kaspiDay("19.03.26")
        env.insertLegacy(date: day, amount: 2317.19, details: "MPOS 4BMART", foreign: (125_000, "VND"),
                         importedAt: Date(timeIntervalSince1970: 2_000))
        env.insertLegacy(date: day, amount: 2312.87, details: "MPOS 4BMART", foreign: (125_000, "VND"),
                         importedAt: Date(timeIntervalSince1970: 1_000))
        env.insertLegacy(date: kaspiDay("30.03.26"), amount: 100, details: "LATEST", importedAt: Date(timeIntervalSince1970: 1_000))
        try env.context.save()
        let before = env.state

        var fixture = StatementFixture(from: "01.04.26", to: "10.04.26")
        fixture.purchase("05.04.26", 700, "NEW SHOP")
        let result = try env.importStatement(fixture)

        let record = try #require(ImportHistory.loadRecords().first)
        #expect(record.removedDuplicateIDs.count == 1)
        #expect(env.transactions.filter { $0.details == "MPOS 4BMART" }.map(\.amount) == [2312.87])

        let summary = try ImportHistory.undo(importedAt: result.importedAt, context: env.context)
        #expect(summary.restoredDuplicatesCount == 1)
        #expect(env.state == before)
    }

    @Test("Выключенная автоочистка ничего не удаляет")
    func autoCleanupDisabled() throws {
        let env = try ImportTestEnvironment()
        ImportStorage.defaults.set(false, forKey: DuplicateCleaner.autoCleanupKey)
        let day = kaspiDay("19.03.26")
        env.insertLegacy(date: day, amount: 2317.19, details: "MPOS 4BMART", foreign: (125_000, "VND"), importedAt: Date(timeIntervalSince1970: 2))
        env.insertLegacy(date: day, amount: 2312.87, details: "MPOS 4BMART", foreign: (125_000, "VND"), importedAt: Date(timeIntervalSince1970: 1))
        try env.context.save()

        #expect(DuplicateCleaner.autoCleanupIfEnabled(context: env.context).isEmpty)
        #expect(env.transactions.count == 2)
    }

    // MARK: - Аналитика

    @Test("Курсовая разница «в плюс» уменьшает расходы категории и мерчанта, а не считается доходом")
    func exchangeRateDifferenceInAnalytics() throws {
        let env = try ImportTestEnvironment()
        var fixture = StatementFixture(from: "01.09.26", to: "29.09.26")
        fixture.purchase("20.09.26", 1000, "GS25")
        fixture.exchangeRateDifference("22.09.26", 10, "GS25")
        fixture.row("25.09.26", 5000, .topUp, "С карты другого банка")
        try env.importStatement(fixture)

        let difference = try #require(env.transactions.first { $0.isExchangeRateDifference })
        #expect(difference.reducesExpensesInAnalytics)
        #expect(difference.countsAsExpenseInAnalytics && !difference.countsAsIncomeInAnalytics)
        #expect(difference.analyticsAmount == -10)

        let snapshot = AnalyticsSnapshotBuilder.build(
            transactions: env.transactions,
            scale: .month,
            anchorDate: kaspiDay("15.09.26"),
            settings: nil,
            trackedRates: []
        )
        let rub = { (kzt: Double) in HistoricalCurrencyConverter.rubAmount(for: kzt, on: kaspiDay("20.09.26"), rates: [], fallbackKztPerRub: 5)! }
        #expect(abs(snapshot.totalExpensesRub - (rub(1000) - rub(10))) < 0.01)
        #expect(abs(snapshot.totalIncomeRub - rub(5000)) < 0.01)
        #expect(snapshot.expenseCount == 1)
        #expect(snapshot.incomeCount == 1)
    }

    @Test("Курсовой разнице без категории при запуске проставляется категория покупок того же мерчанта")
    func categorySyncForLegacyDifferences() throws {
        let env = try ImportTestEnvironment()
        env.insertLegacy(date: kaspiDay("20.09.26"), amount: 1000, details: "GS25", importedAt: Date(timeIntervalSince1970: 1))
        let difference = env.insertLegacy(date: kaspiDay("22.09.26"), amount: 10, details: "GS25", kind: .income, importedAt: Date(timeIntervalSince1970: 1))
        difference.note = Transaction.exchangeRateDifferenceNote
        try env.context.save()

        ExchangeRateDifferenceCategorySync.run(context: env.context)
        #expect(difference.categoryName == "Еда")
    }

    // MARK: - Сверка баланса

    @Test("Сверка баланса: без начального остатка расходится, «Выровнять» — сходится, повторно не дублирует")
    func balanceReconciliation() throws {
        let env = try ImportTestEnvironment()
        var first = StatementFixture(from: "01.03.26", to: "19.03.26", opening: 100_000)
        first.purchase("10.03.26", 500, "COFFEE BOOM")
        try env.importStatement(first)

        let check = try #require(BalanceReconciliation.check(statement: first.statement, transactions: env.transactions, kaspi: env.kaspi))
        #expect(check.statementBalance == 99_500)
        #expect(check.appBalance == -500)
        #expect(!check.isMatching)

        try BalanceReconciliation.align(check, kaspi: env.kaspi, context: env.context)
        let aligned = try #require(BalanceReconciliation.check(statement: first.statement, transactions: env.transactions, kaspi: env.kaspi))
        #expect(aligned.isMatching)

        let adjustment = try #require(env.transactions.first { $0.details == BalanceReconciliation.adjustmentDetails })
        #expect(adjustment.kind == .transfer && adjustment.amount == 100_000 && adjustment.toAccount?.name == "Kaspi")
        #expect(adjustment.date < kaspiDay("10.03.26"))

        // Следующая выписка, в которой не хватает операции на 300 ₸, которой нет в базе.
        var second = StatementFixture(from: "19.03.26", to: "30.03.26", opening: 99_500)
        second.purchase("25.03.26", 1200, "GOOD MART")
        second.purchase("26.03.26", 300, "MISSING")
        try env.importStatement(second)
        let missing = try #require(env.transactions.first { $0.details == "MISSING" })
        env.context.delete(missing)
        try env.context.save()

        let next = try #require(BalanceReconciliation.check(statement: second.statement, transactions: env.transactions, kaspi: env.kaspi))
        #expect(abs(next.difference + 300) < 0.001, "расхождение ровно на пропавшую операцию")

        try BalanceReconciliation.align(next, kaspi: env.kaspi, context: env.context)
        #expect(env.transactions.filter { $0.details == BalanceReconciliation.adjustmentDetails }.count == 1)
    }
}
