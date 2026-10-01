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
        note: String? = nil
    ) -> Transaction {
        let transaction = Transaction(
            date: day,
            kindRaw: kind.rawValue,
            amount: rub * 5,
            currencyCode: "KZT",
            details: details,
            rubAmount: rub,
            categoryName: category,
            subcategoryName: subcategory,
            note: note
        )
        context.insert(transaction)
        return transaction
    }

    private func categoryTotals() -> [AnalyticsCategoryTotal] {
        let transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        return AnalyticsSnapshotBuilder.build(
            transactions: transactions,
            scale: .month,
            anchorDate: day,
            settings: nil,
            trackedRates: []
        ).categoryTotals
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

    @Test("Курсовая разница «в плюс» уменьшает подкатегорию покупок того же мерчанта")
    func refundGoesToMerchantSubcategory() throws {
        add(100, "Еда", "Кафе и кофейни", details: "GS25")
        add(60, "Еда", "Продукты", details: "CU")
        add(1, "Еда", details: "GS25", kind: .income, note: Transaction.exchangeRateDifferenceNote)

        let food = try #require(categoryTotals().first { $0.category == "Еда" })
        #expect(food.total == 159)
        #expect(food.count == 2)
        #expect(food.subcategories.first { $0.name == "Кафе и кофейни" }?.total == 99)
        #expect(food.subcategories.first { $0.name == "Продукты" }?.total == 60)
        #expect(!food.subcategories.contains { $0.name == "Другое" })
    }

    @Test("Список операций подкатегории совпадает с плиткой")
    func drillDownMatchesTile() {
        let cafe = add(100, "Еда", "Кафе и кофейни")
        let other = add(20, "Еда")
        let fun = add(40, "Развлечения")

        #expect(CategoryTotalsAccumulator.subcategoryName(of: cafe) == "Кафе и кофейни")
        #expect(CategoryTotalsAccumulator.subcategoryName(of: other) == "Другое")
        #expect(CategoryTotalsAccumulator.subcategoryName(of: fun) == nil)
    }
}
