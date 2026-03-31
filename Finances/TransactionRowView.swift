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
        VStack(alignment: .leading, spacing: 7) {
            topRow
            secondaryAmountsRow
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

            VStack(alignment: .trailing, spacing: 2) {
                Text(primaryAmountText)
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(transaction.date, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var secondaryAmountsRow: some View {
        if let text = secondaryAmountsText {
            HStack {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()
            }
        }
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            Image(systemName: transaction.kind.systemImage)
                .font(.caption2)
                .foregroundStyle(kindTint)

            Text(transaction.kind.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let accountText {
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(accountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

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
                return "\(formattedNumber(rub)) ₽"
            } else {
                return "\(formattedNumber(transaction.amount)) \(transaction.currencyCode)"
            }

        case .transfer:
            if transaction.isCrossCurrencyTransfer {
                return "\(formattedNumber(transaction.creditedAmount)) \(transaction.creditedCurrencyCode)"
            } else {
                return "\(formattedNumber(transaction.amount)) \(transaction.currencyCode)"
            }
        }
    }

    private var secondaryAmountsText: String? {
        switch transaction.kind {
        case .expense, .income:
            var parts: [String] = []

            if let foreignAmount = transaction.foreignAmount,
               let foreignCurrencyCode = transaction.foreignCurrencyCode {
                parts.append("\(formattedNumber(abs(foreignAmount))) \(foreignCurrencyCode)")
            }

            if resolvedRubAmount != nil || transaction.foreignAmount != nil {
                parts.append("\(formattedNumber(transaction.amount)) \(transaction.currencyCode)")
            }

            return parts.isEmpty ? nil : parts.joined(separator: " • ")

        case .transfer:
            if transaction.isCrossCurrencyTransfer {
                return "\(formattedNumber(transaction.amount)) \(transaction.currencyCode) → \(formattedNumber(transaction.creditedAmount)) \(transaction.creditedCurrencyCode)"
            } else {
                return nil
            }
        }
    }

    private var accountText: String? {
        switch transaction.kind {
        case .expense:
            return transaction.fromAccount?.name
        case .income:
            return transaction.toAccount?.name
        case .transfer:
            let from = transaction.fromAccount?.name ?? "?"
            let to = transaction.toAccount?.name ?? "?"
            return "\(from) → \(to)"
        }
    }

    private var kindTint: Color {
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
