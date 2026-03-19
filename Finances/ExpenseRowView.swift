import SwiftUI

struct ExpenseRowView: View {
    let expense: Expense

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(expense.details)
                    .font(.headline)
                    .lineLimit(2)

                Spacer()

                Text(formattedAmount(expense.amount, currency: expense.accountCurrency))
                    .font(.headline)
                    .foregroundStyle(amountColor(expense.amount))
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text(expense.operationType)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let category = expense.category {
                    Text("• \(category.title)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

    private func amountColor(_ amount: Double) -> Color {
        amount < 0 ? .red : .green
    }
}
