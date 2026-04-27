import SwiftUI
import SwiftData

struct ExpenseRowView: View {
    let expense: Expense

    @Environment(\.modelContext) private var modelContext

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

                categoryMenu

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

    @ViewBuilder
    private var categoryMenu: some View {
        Menu {
            ForEach(categories) { category in
                Button {
                    expense.categoryName = category.name
                    saveChanges()
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: category.colorHex) ?? .gray)
                            .frame(width: 16, height: 16)
                            .overlay {
                                CategoryIconView(category: category, size: 30)
                            }

                        Text(category.name)

                        if expense.categoryName == category.name {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            categoryLabel
        }
    }

    @ViewBuilder
    private var categoryLabel: some View {
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

                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Text("• \(categoryName)")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 4) {
                Text("Другое")
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save category change: \(error)")
        }
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
