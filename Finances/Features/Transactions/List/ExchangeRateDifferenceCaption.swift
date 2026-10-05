import SwiftUI

/// Строка под покупкой: курсовая разница, которую Kaspi провёл позже, и итоговое списание.
struct ExchangeRateDifferenceCaption: View {
    let purchase: Transaction
    let folded: FoldedExchangeRateDifferences

    var body: some View {
        let differences = folded.differences(for: purchase)

        if !differences.isEmpty {
            let charge = differences.reduce(0) { $0 + ExchangeRateDifferenceMatcher.signedCharge(of: $1) }

            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2)

                Text("Курсовая разница \(Self.format(-charge, signed: true)) · итого \(Self.format(-folded.finalAmount(for: purchase), signed: true))")
                    .font(.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
        }
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","
        return formatter
    }()

    private static func format(_ value: Double, signed: Bool) -> String {
        let number = formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        let sign = signed ? (value < 0 ? "− " : "+ ") : ""
        return "\(sign)\(number) ₸"
    }
}
