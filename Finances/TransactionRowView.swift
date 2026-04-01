import SwiftUI
import SwiftData

struct TransactionRowView: View {
    @Environment(\.modelContext) private var modelContext

    let transaction: Transaction

    @Query
    private var settingsList: [AppSettings]

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    private var settings: AppSettings? {
        settingsList.first
    }

    private var categoryItem: ExpenseCategoryItem? {
        CategoryLookup.findCategory(named: transaction.categoryName, in: categories)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topRow

            if let text = secondaryAmountsText {
                secondaryAmountsRow(text: text)
            }

            metaRow

            if let note = transaction.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(transaction.details)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                categoryMenu
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                Text(primaryAmountText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(primaryAmountColor)
                    .multilineTextAlignment(.trailing)

                Text(transaction.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func secondaryAmountsRow(text: String) -> some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(secondaryAmountColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()
        }
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            Image(systemName: metaIconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(metaIconColor)

            Text(accountLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
    }

    @ViewBuilder
    private var categoryMenu: some View {
        if transaction.kind == .expense {
            Menu {
                Button {
                    updateCategory(nil)
                } label: {
                    HStack {
                        Text("Без категории")
                        if transaction.categoryName == nil {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                ForEach(categories) { category in
                    Button {
                        updateCategory(category.name)
                    } label: {
                        HStack {
                            Text(category.name)

                            if transaction.categoryName == category.name {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                categoryChipLabel
            }
            .menuStyle(.borderlessButton)
        }
    }

    @ViewBuilder
    private var categoryChipLabel: some View {
        let name = transaction.categoryName ?? "Без категории"

        if let categoryItem {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: categoryItem.colorHex) ?? .gray)
                    .frame(width: 16, height: 16)
                    .overlay {
                        Image(systemName: categoryItem.iconName)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }

                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.10))
            .clipShape(Capsule())
        } else {
            HStack(spacing: 5) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.10))
            .clipShape(Capsule())
        }
    }

    private var resolvedRubAmount: Double? {
        TransactionRubConverter.displayRubAmount(
            for: transaction,
            settings: settings,
            trackedRates: trackedRates
        )
    }

    private var primaryAmountText: String {
        switch transaction.kind {
        case .expense, .income:
            if let rub = resolvedRubAmount {
                return signedFormattedAmount(
                    rub,
                    currency: "₽",
                    kind: transaction.kind
                )
            } else {
                return signedFormattedAmount(
                    transaction.amount,
                    currency: CurrencyDisplay.normalizedCode(from: transaction.currencyCode),
                    kind: transaction.kind
                )
            }

        case .transfer:
            if transaction.isCrossCurrencyTransfer {
                return formattedUnsignedAmount(
                    transaction.creditedAmount,
                    currency: CurrencyDisplay.normalizedCode(from: transaction.creditedCurrencyCode)
                )
            } else {
                return formattedUnsignedAmount(
                    transaction.amount,
                    currency: CurrencyDisplay.normalizedCode(from: transaction.currencyCode)
                )
            }
        }
    }

    private var secondaryAmountsText: String? {
        switch transaction.kind {
        case .expense, .income:
            var parts: [String] = []

            if let foreignAmount = transaction.foreignAmount,
               let foreignCurrencyCode = transaction.foreignCurrencyCode {
                parts.append(
                    signedFormattedAmount(
                        foreignAmount,
                        currency: CurrencyDisplay.normalizedCode(from: foreignCurrencyCode),
                        kind: transaction.kind
                    )
                )
            }

            if resolvedRubAmount != nil || transaction.foreignAmount != nil {
                parts.append(
                    signedFormattedAmount(
                        transaction.amount,
                        currency: CurrencyDisplay.normalizedCode(from: transaction.currencyCode),
                        kind: transaction.kind
                    )
                )
            }

            return parts.isEmpty ? nil : parts.joined(separator: " • ")

        case .transfer:
            if transaction.isCrossCurrencyTransfer {
                return "\(formattedUnsignedAmount(transaction.amount, currency: CurrencyDisplay.normalizedCode(from: transaction.currencyCode))) → \(formattedUnsignedAmount(transaction.creditedAmount, currency: CurrencyDisplay.normalizedCode(from: transaction.creditedCurrencyCode)))"
            } else {
                return nil
            }
        }
    }

    private var accountLine: String {
        switch transaction.kind {
        case .expense:
            return transaction.fromAccount?.name ?? "Без счета"

        case .income:
            return transaction.toAccount?.name ?? "Без счета"

        case .transfer:
            let from = transaction.fromAccount?.name ?? "Без счета"
            let to = transaction.toAccount?.name ?? "Без счета"
            return "\(from) → \(to)"
        }
    }

    private var primaryAmountColor: Color {
        switch transaction.kind {
        case .expense:
            return .red
        case .income:
            return .green
        case .transfer:
            return .primary
        }
    }

    private var secondaryAmountColor: Color {
        switch transaction.kind {
        case .expense:
            return .red.opacity(0.75)
        case .income:
            return .green.opacity(0.75)
        case .transfer:
            return .secondary
        }
    }

    private var metaIconName: String {
        switch transaction.kind {
        case .expense:
            return "arrow.up.circle.fill"
        case .income:
            return "arrow.down.circle.fill"
        case .transfer:
            return "arrow.left.arrow.right.circle.fill"
        }
    }

    private var metaIconColor: Color {
        switch transaction.kind {
        case .expense:
            return .red.opacity(0.75)
        case .income:
            return .green.opacity(0.75)
        case .transfer:
            return .secondary
        }
    }

    private func updateCategory(_ name: String?) {
        transaction.categoryName = name
        try? modelContext.save()
    }

    private func signedFormattedAmount(
        _ value: Double,
        currency: String,
        kind: TransactionKind
    ) -> String {
        let sign: String
        switch kind {
        case .expense:
            sign = "-"
        case .income:
            sign = "+"
        case .transfer:
            sign = ""
        }

        let number = formattedNumber(abs(value))
        return sign.isEmpty ? "\(number) \(currency)" : "\(sign) \(number) \(currency)"
    }

    private func formattedUnsignedAmount(
        _ value: Double,
        currency: String
    ) -> String {
        "\(formattedNumber(abs(value))) \(currency)"
    }

    private func formattedNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        return formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
    }
}
