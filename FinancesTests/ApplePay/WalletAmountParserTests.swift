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
}
