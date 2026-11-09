//
//  TransactionDaySections.swift
//  Finances
//
//  Операции по дням для списков в стиле .insetGrouped: каждый день — своя
//  карточка, над ней дата и итог дня.
//

import SwiftUI
import SwiftData

struct TransactionDaySections: View {
    /// Как открывается операция по касанию.
    enum LinkStyle {
        /// Ссылка с экраном операции — для стеков без своего пути.
        case destination
        /// Ссылка со значением `PersistentIdentifier` — экран задаёт
        /// `navigationDestination(for: PersistentIdentifier.self)` сам.
        case value
    }

    let transactions: [Transaction]
    let folded: FoldedExchangeRateDifferences
    /// Что считать в итоге дня: у «Расходов» — только расходы и т. д.
    var filter: TransactionKindFilter = .all
    var linkStyle: LinkStyle = .destination
    /// Удаление свайпом; nil — без удаления.
    var onDelete: ((Transaction) -> Void)?

    var body: some View {
        ForEach(TransactionSectionGrouper.groupedByDay(transactions), id: \.date) { section in
            Section {
                ForEach(section.items) { transaction in
                    link(for: transaction)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if let onDelete {
                                Button(role: .destructive) {
                                    onDelete(transaction)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                        }
                }
            } header: {
                TransactionDayHeader(
                    date: section.date,
                    total: TransactionDayTotal.make(for: section.items, folded: folded, filter: filter)
                )
            }
        }
    }

    @ViewBuilder
    private func link(for transaction: Transaction) -> some View {
        switch linkStyle {
        case .destination:
            NavigationLink {
                TransactionDetailView(transaction: transaction)
            } label: {
                TransactionListRow(transaction: transaction, folded: folded)
            }

        case .value:
            NavigationLink(value: transaction.persistentModelID) {
                TransactionListRow(transaction: transaction, folded: folded)
            }
        }
    }
}

/// Строка списка: операция и, если есть, её курсовая разница под ней.
struct TransactionListRow: View {
    let transaction: Transaction
    let folded: FoldedExchangeRateDifferences

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TransactionRowView(transaction: transaction)
            ExchangeRateDifferenceCaption(purchase: transaction, folded: folded)
                // Вровень с текстом строки, а не с иконкой.
                .padding(.leading, 50)
        }
    }
}

/// Заголовок дня: «Сегодня», «Вчера» или дата — и итог дня справа.
struct TransactionDayHeader: View {
    let date: Date
    let total: TransactionDayTotal?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Self.title(for: date))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            if let total {
                Text(total.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(total.color)
                    .monospacedDigit()
            }
        }
        .textCase(nil)
    }

    static func title(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInYesterday(date) { return "Вчера" }

        let formatter = calendar.isDate(date, equalTo: .now, toGranularity: .year)
            ? currentYearFormatter
            : otherYearFormatter
        return formatter.string(from: date)
    }

    // Один набор на все заголовки: создавать DateFormatter на каждый день дорого.
    private static let currentYearFormatter = makeFormatter("d MMMM, EEEEEE")
    private static let otherYearFormatter = makeFormatter("d MMMM yyyy")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = format
        return formatter
    }
}

/// Итог дня в рублях: доходы минус расходы, а при фильтре — только его вид.
struct TransactionDayTotal {
    let text: String
    let color: Color

    static func make(
        for transactions: [Transaction],
        folded: FoldedExchangeRateDifferences,
        filter: TransactionKindFilter
    ) -> TransactionDayTotal? {
        // Курсовые разницы спрятаны под своими покупками — их сумма идёт в день покупки.
        let expenses = transactions
            .filter { $0.kind == .expense }
            .reduce(0.0) { $0 + (folded.finalRubAmount(for: $1) ?? $1.rubAmount ?? 0) }
        let income = transactions
            .filter { $0.kind == .income }
            .reduce(0.0) { $0 + ($1.rubAmount ?? 0) }

        let total: Double
        switch filter {
        case .all:
            total = income - expenses
        case .expenses:
            total = -expenses
        case .income:
            total = income
        case .transfers:
            return nil
        }

        guard total.rounded() != 0 else { return nil }

        let sign = total < 0 ? "−" : "+"
        let number = formatter.string(from: NSNumber(value: abs(total).rounded())) ?? "\(abs(total))"
        return TransactionDayTotal(text: "\(sign)\(number) ₽", color: total < 0 ? .red : .green)
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        return formatter
    }()
}
