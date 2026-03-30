import SwiftUI
import SwiftData

struct ExpenseRowView: View {
    let expense: Expense

    @Query
    private var settingsList: [AppSettings]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    private var settings: AppSettings? {
        settingsList.first
    }

    private var categoryItem: ExpenseCategoryItem? {
        CategoryLookup.findCategory(named: expense.categoryName, in: categories)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(expense.details)
                    .font(.headline)
                    .lineLimit(2)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(formattedAmount(expense.amount, currency: expense.accountCurrency))
                        .font(.headline)
                        .foregroundStyle(amountColor(expense.amount))
                        .multilineTextAlignment(.trailing)

                    if let rubAmount = expense.rubAmount {
                        Text(formattedRubAmount(rubAmount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Text(expense.operationType)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let categoryName = expense.categoryName {
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

                            Text(categoryName)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("• \(categoryName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(expense.date, format: .dateTime.day().month().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let foreignAmount = expense.foreignAmount,
               let foreignCurrency = expense.foreignCurrency {
                Text("(\(formattedAmount(foreignAmount, currency: foreignCurrency)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let note = expense.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        let sign = amount < 0 ? "-" : "+"
        let number = formatter.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"

        return "\(sign) \(number) \(currency)"
    }

    private func formattedRubAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        let sign = amount < 0 ? "-" : "+"
        let number = formatter.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"

        return "\(sign) \(number) ₽"
    }

    private func amountColor(_ amount: Double) -> Color {
        amount < 0 ? .red : .green
    }
}
