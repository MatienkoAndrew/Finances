import Foundation
import Testing
@testable import Finances

@MainActor
@Suite("Разбор выписки Kaspi")
struct KaspiStatementParserTests {
    /// Строки из настоящей выписки (после `PDFLayoutTextExtractor`).
    private let realLines = [
        "ВЫПИСКА",
        "по Kaspi Gold за период с 18.06.26 по 29.09.26",
        "Доступно на 29.09.26: + 70 963,02 ₸ Валюта счета: теңге",
        "Доступно на 18.06.26 + 50 438,63 ₸ Остаток зарплатных денег 0,00 ₸",
        "Пополнения + 0,00 ₸ Другие пополнения 0,00 ₸",
        "Переводы + 0,00 ₸",
        "Переводы на свои счета + 0,00 ₸",
        "Покупки - 4 629,19 ₸",
        "Снятия + 0,00 ₸",
        "Разное + 0,00 ₸",
        "Дата Сумма Операция Детали",
        "29.09.26 - 4 613,91 ₸ Покупка MAMSTERCHILAB ITAEWONJ",
        "(- 14 000,00 KRW)",
        "29.09.26 + 4,57 ₸ Покупка GS25SEOKYOTEUNTEUNJUM",
        "Курсовая разница",
        "АОАО ««KKaspi Bank», БИК CASPKZKA, www.kaspi.kz",
        "Приложение к Справке №1287342082 от 29 сентября 2026",
        "29.09.26 + 7,63 ₸ Покупка (JOO)CONUPUB(Corner Pu",
        "Курсовая разница",
        "28.09.26 - 27,48 ₸ Покупка 7-ELEVEN",
        "- Сумма заблокирована. Банк ожидает подтверждения от платежной системы."
    ]

    private var statement: KaspiStatement {
        KaspiStatementParser.parse(lines: StatementFixture.textLines(realLines))
    }

    @Test("Знак суммы берётся из выписки: «+» у курсовой разницы — зачисление")
    func signIsPreserved() {
        let rows = statement.rows
        #expect(rows.count == 4)
        #expect(rows[0].amount == -4613.91)
        #expect(rows[1].amount == 4.57)
        #expect(rows[1].isExchangeRateDifference)
        #expect(!rows[0].isExchangeRateDifference)
    }

    @Test("Сумма в валюте со следующей строки, со знаком")
    func foreignAmount() {
        let row = statement.rows[0]
        #expect(row.foreignAmount == -14000)
        #expect(row.foreignCurrency == "KRW")
        #expect(statement.rows[1].foreignAmount == nil)
    }

    @Test("Пунктуация в названиях мерчантов не теряется")
    func detailsKeepPunctuation() {
        #expect(statement.rows[2].details == "(JOO)CONUPUB(Corner Pu")
        #expect(statement.rows[3].details == "7-ELEVEN")
    }

    @Test("Колонтитул и шапка страницы не ломают операции; сноска о блокировке не цепляется к строке")
    func pageBreaks() {
        let rows = statement.rows
        #expect(rows[2].amount == 7.63 && rows[2].isExchangeRateDifference)
        #expect(rows[3].amount == -27.48 && !rows[3].isExchangeRateDifference && rows[3].foreignAmount == nil)
        #expect(statement.unrecognizedLines.isEmpty)
    }

    @Test("Период, остатки и итоги по типам")
    func header() {
        let statement = statement
        #expect(statement.periodStart == kaspiDay("18.06.26"))
        #expect(statement.periodEnd == kaspiDay("29.09.26"))
        #expect(statement.closingBalance == 70963.02)
        #expect(statement.availableBalances[kaspiDay("18.06.26")] == 50438.63)
        #expect(statement.summaryTotals[.purchase] == -4629.19)
        #expect(statement.mismatchedTypes.isEmpty)
    }

    @Test("Несошедшиеся итоги и нераспознанные строки видны")
    func detectsProblems() {
        var lines = realLines
        lines[7] = "Покупки - 5 000,00 ₸"
        lines.append("27.09.26 - 1,00 ₸ Непонятно ЧТО-ТО")
        let statement = KaspiStatementParser.parse(lines: StatementFixture.textLines(lines))
        #expect(statement.mismatchedTypes == [.purchase])
        #expect(statement.unrecognizedLines == ["27.09.26 - 1,00 ₸ Непонятно ЧТО-ТО"])
    }

    @Test("Дата операции — полдень по времени Kaspi")
    func datesAtKaspiNoon() {
        let date = statement.rows[0].date
        #expect(KaspiStatementParser.calendar.component(.hour, from: date) == 12)
        #expect(date == kaspiDay("29.09.26"))
    }

    @Test("Сборщик тестовых выписок даёт согласованные итоги")
    func fixtureIsConsistent() {
        var fixture = StatementFixture(from: "01.03.26", to: "19.03.26")
        fixture.purchase("19.03.26", 9756.60, "OPENAI *CHATGPT SUBSCR", fx: (20, "USD"))
        fixture.row("18.03.26", 121_900, .topUp, "С карты другого банка")
        fixture.row("17.03.26", -20_000, .withdrawal, "Банкомат ATM KHU PHO TAY", fx: (-1_000_000, "VND"))
        let statement = fixture.statement
        #expect(statement.rows.count == 3)
        #expect(statement.mismatchedTypes.isEmpty)
        #expect(abs((statement.closingBalance ?? 0) - fixture.closing) < 0.001)
    }
}
