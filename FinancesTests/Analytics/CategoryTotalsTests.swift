import Foundation
import SwiftData
import Testing
@testable import Finances

@MainActor
@Suite("Аналитика: категории и подкатегории")
struct CategoryTotalsTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let day = kaspiDay("15.04.26")

    init() throws {
        container = try ModelContainer(
            for: Transaction.self, Account.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    @discardableResult
    private func add(
        _ rub: Double,
        _ category: String?,
        _ subcategory: String? = nil,
        details: String = "SHOP",
        kind: TransactionKind = .expense,
        note: String? = nil,
        date: Date? = nil,
        foreign: Double? = nil
    ) -> Transaction {
        let transaction = Transaction(
            date: date ?? day,
            kindRaw: kind.rawValue,
            amount: rub * 5,
            currencyCode: "KZT",
            details: details,
            foreignAmount: foreign,
            foreignCurrencyCode: foreign == nil ? nil : "KRW",
            rubAmount: rub,
            categoryName: category,
            subcategoryName: subcategory,
            note: note
        )
        context.insert(transaction)
        return transaction
    }

    private func snapshot(month: Date? = nil) -> AnalyticsSnapshot {
        let transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        return AnalyticsSnapshotBuilder.build(
            transactions: transactions,
            scale: .month,
            anchorDate: month ?? day,
            settings: nil,
            trackedRates: []
        )
    }

    private func categoryTotals(month: Date? = nil) -> [AnalyticsCategoryTotal] {
        snapshot(month: month).categoryTotals
    }

    private func addDifference(_ rub: Double, _ category: String?, details: String, kind: TransactionKind = .income, date: Date) {
        add(rub, category, details: details, kind: kind, note: Transaction.exchangeRateDifferenceNote, date: date)
    }

    @Test("Категория — сумма подкатегорий; без подкатегории — в «Другое»")
    func subcategoriesSumUp() throws {
        add(100, "Еда", "Кафе и кофейни")
        add(50, "Еда", "Кафе и кофейни")
        add(30, "Еда", "Продукты")
        add(20, "Еда")

        let food = try #require(categoryTotals().first { $0.category == "Еда" })
        #expect(food.total == 200)
        #expect(food.count == 4)
        #expect(food.subcategories.map(\.name) == ["Кафе и кофейни", "Продукты", "Другое"])
        #expect(food.subcategories.map(\.total) == [150, 30, 20])
        #expect(food.subcategories.map(\.count) == [2, 1, 1])
        #expect(food.subcategories.first?.emoji == "☕️")
        #expect(abs(food.subcategories.reduce(0) { $0 + $1.total } - food.total) < 0.001)
    }

    @Test("Без разбивки: подкатегории не выбирали или их у категории нет")
    func noBreakdown() throws {
        add(100, "Еда")
        add(40, "Развлечения")
        add(10, nil)

        let totals = categoryTotals()
        #expect(totals.allSatisfy { $0.subcategories.isEmpty })
        #expect(totals.map(\.category) == ["Еда", "Развлечения", CategoryTotalsAccumulator.uncategorized])
    }

    @Test("Курсовая разница считается внутри своей покупки: её подкатегория, без отдельной операции")
    func differenceGoesToItsPurchase() throws {
        add(100, "Еда", "Кафе и кофейни", details: "GS25", foreign: 2_900)
        add(60, "Еда", "Продукты", details: "CU")
        addDifference(1, "Еда", details: "GS25", date: kaspiDay("17.04.26"))

        let food = try #require(categoryTotals().first { $0.category == "Еда" })
        #expect(food.total == 159)
        #expect(food.count == 2)
        #expect(food.subcategories.first { $0.name == "Кафе и кофейни" }?.total == 99)
        #expect(food.subcategories.first { $0.name == "Продукты" }?.total == 60)
        #expect(!food.subcategories.contains { $0.name == "Другое" })
    }

    @Test("Курсовая разница из следующего месяца уходит в месяц покупки — без минусов")
    func differenceFromNextMonth() throws {
        add(100, "Покупки", "Одежда и обувь", details: "UNIQLO", date: kaspiDay("29.03.26"), foreign: 2_900)
        addDifference(2, "Покупки", details: "UNIQLO", date: kaspiDay("02.04.26"))

        let april = snapshot(month: kaspiDay("15.04.26"))
        #expect(april.categoryTotals.isEmpty)
        #expect(april.merchantTotals.isEmpty)
        #expect(april.totalExpensesRub == 0)
        #expect(april.expenseCount == 0)

        let march = snapshot(month: kaspiDay("15.03.26"))
        let shopping = try #require(march.categoryTotals.first { $0.category == "Покупки" })
        #expect(shopping.total == 98)
        #expect(shopping.count == 1)
        #expect(march.totalExpensesRub == 98)
    }

    @Test("Курсовая разница без своей покупки в аналитике не учитывается")
    func unmatchedDifferenceIgnored() {
        add(100, "Еда", details: "CU")
        addDifference(3, "Здоровье и красота", details: "PHARMACY", date: day)

        let totals = categoryTotals()
        #expect(totals.map(\.category) == ["Еда"])
        #expect(snapshot().totalExpensesRub == 100)
    }

    @Test("Список операций подкатегории совпадает с плиткой")
    func drillDownMatchesTile() {
        let cafe = add(100, "Еда", "Кафе и кофейни")
        let other = add(20, "Еда")
        let cash = add(40, "Снятие наличных")

        #expect(CategoryTotalsAccumulator.subcategoryName(of: cafe) == "Кафе и кофейни")
        #expect(CategoryTotalsAccumulator.subcategoryName(of: other) == "Другое")
        #expect(CategoryTotalsAccumulator.subcategoryName(of: cash) == nil)
    }
}
