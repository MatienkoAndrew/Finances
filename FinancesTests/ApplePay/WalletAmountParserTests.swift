import Testing
@testable import Finances

struct WalletAmountParserTests {
    @Test func dotBeforeThreeDigitsIsThousandsSeparator() {
        #expect(
            WalletAmountParser.parse("65.000 ₫")
                == WalletAmountParser.Amount(
                    value: 65_000,
                    currencyCode: "VND"
                )
        )
    }

    @Test("Доллары с приставкой и юань — своя валюта, голый «$» — доллар США", arguments: [
        ("NT$79,00", 79.0, "TWD"),
        ("79,00 NT$", 79.0, "TWD"),
        ("NT$3,100.00", 3_100.0, "TWD"),
        ("HK$45.50", 45.5, "HKD"),
        ("CA$10.00", 10.0, "CAD"),
        ("A$10.00", 10.0, "AUD"),
        ("AU$10.00", 10.0, "AUD"),
        ("NZ$12.00", 12.0, "NZD"),
        ("S$8.20", 8.2, "SGD"),
        ("CN¥81,00", 81.0, "CNY"),
        ("¥1,200", 1_200.0, "JPY"),
        ("US$4.50", 4.5, "USD"),
        ("$4.50", 4.5, "USD")
    ])
    func dollarAndYenSymbols(text: String, value: Double, code: String) {
        #expect(WalletAmountParser.parse(text) == WalletAmountParser.Amount(value: value, currencyCode: code))
    }
}
