import Foundation
import SwiftData
import Testing
@testable import Finances

@MainActor
@Suite("Курсовая разница под своей покупкой")
struct ExchangeRateDifferenceMatcherTests {
    private func purchase(_ day: Int, _ amount: Double, _ merchant: String = "GS25") -> ExchangeRateDifferenceMatcher.Item {
        .init(day: day, merchant: merchant, amount: amount, isDifference: false, isForeignPurchase: true)
    }

    private func difference(_ day: Int, _ amount: Double, _ merchant: String = "GS25") -> ExchangeRateDifferenceMatcher.Item {
        .init(day: day, merchant: merchant, amount: amount, isDifference: true, isForeignPurchase: false)
    }

    @Test("Единственная покупка того же мерчанта")
    func singleCandidate() {
        let items = [purchase(10, 727.34), purchase(10, 500, "CU"), difference(13, 4.57)]
        #expect(ExchangeRateDifferenceMatcher.pair(items) == [2: 0])
    }

    @Test("Из нескольких покупок — та, что примерно за 3 дня; у каждой покупки одна разница")
    func prefersTypicalGapAndOneToOne() {
        let items = [
            purchase(1, 1000),     // 0: за 9 дней
            purchase(7, 1000),     // 1: за 3 дня
            purchase(8, 1000),     // 2: за 2 дня
            difference(10, 5),     // 3
            difference(10, 6)      // 4
        ]
        let pairs = ExchangeRateDifferenceMatcher.pair(items)
        #expect(pairs[3] == 1)
        #expect(pairs[4] == 2)
        #expect(Set(pairs.values).count == pairs.count)
    }

    @Test("Не подходят: покупка после разницы, старше 30 дней, разница больше 3% суммы, другой мерчант")
    func rejectsImplausible() {
        let items = [
            purchase(20, 1000),          // позже разницы
            purchase(1, 1000),           // 39 дней назад
            purchase(38, 100),           // разница 5 > 3% от 100
            purchase(38, 1000, "CU"),    // другой мерчант
            difference(40, 5)
        ]
        #expect(ExchangeRateDifferenceMatcher.pair(items).isEmpty)
    }

    @Test("Импорт выписки: курсовые разницы прячутся под покупками, итог учитывает доплату и возврат")
    func foldAfterImport() throws {
        let env = try ImportTestEnvironment()
        var fixture = StatementFixture(from: "15.09.26", to: "29.09.26")
        fixture.purchase("20.09.26", 727.34, "7-ELEVEN", fx: (2200, "KRW"))
        fixture.purchase("21.09.26", 1624.17, "SSIYU(CU) YUNNAMYBILDI", fx: (4900, "KRW"))
        fixture.exchangeRateDifference("23.09.26", 4.57, "7-ELEVEN")
        fixture.row("24.09.26", -0.48, .purchase, "SSIYU(CU) YUNNAMYBILDI")
        fixture.rows[fixture.rows.count - 1].isExchangeRateDifference = true
        fixture.exchangeRateDifference("25.09.26", 3.00, "NO SUCH SHOP")
        try env.importStatement(fixture)

        let folded = ExchangeRateDifferenceMatcher.fold(env.transactions)
        #expect(folded.foldedIDs.count == 2, "разница без покупки остаётся отдельной строкой")

        let seven = try #require(env.transactions.first { $0.details == "7-ELEVEN" && !$0.isExchangeRateDifference })
        #expect(abs(folded.finalAmount(for: seven) - 722.77) < 0.001)

        let cu = try #require(env.transactions.first { $0.details.hasPrefix("SSIYU") && !$0.isExchangeRateDifference })
        #expect(abs(folded.finalAmount(for: cu) - 1624.65) < 0.001)

        let orphan = try #require(env.transactions.first { $0.details == "NO SUCH SHOP" })
        #expect(!folded.foldedIDs.contains(orphan.persistentModelID))
    }
}
