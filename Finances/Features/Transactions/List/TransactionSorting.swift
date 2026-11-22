//
//  TransactionSorting.swift
//  Finances
//
//  Сортировка списков, которые открываются из аналитики: операции по дням
//  или по сумме, категории по сумме, числу покупок или названию.
//

import SwiftUI
import SwiftData

/// Порядок операций в списках из аналитики. Выбор запоминается.
enum TransactionListSort: String, CaseIterable, Identifiable {
    case date
    case amountDescending
    case amountAscending

    static let storageKey = "analytics.transactionSort"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: return "По дате"
        case .amountDescending: return "Сначала крупные"
        case .amountAscending: return "Сначала мелкие"
        }
    }

    var systemImage: String {
        switch self {
        case .date: return "calendar"
        case .amountDescending: return "arrow.down.circle"
        case .amountAscending: return "arrow.up.circle"
        }
    }
}

/// Порядок категорий в аналитике. Выбор запоминается.
enum CategoryListSort: String, CaseIterable, Identifiable {
    case amount
    case count
    case name

    static let storageKey = "analytics.categorySort"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amount: return "По сумме"
        case .count: return "По числу покупок"
        case .name: return "По названию"
        }
    }

    var systemImage: String {
        switch self {
        case .amount: return "rublesign.circle"
        case .count: return "number.circle"
        case .name: return "textformat"
        }
    }

    func sorted(_ items: [AnalyticsCategoryTotal]) -> [AnalyticsCategoryTotal] {
        switch self {
        case .amount:
            return items.sorted { $0.total > $1.total }
        case .count:
            return items.sorted { ($0.count, $0.total) > ($1.count, $1.total) }
        case .name:
            return items.sorted { $0.category.localizedCompare($1.category) == .orderedAscending }
        }
    }
}

/// Кнопка-меню выбора порядка: иконка в панели или рядом с заголовком.
struct SortMenu<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    let systemImage: (Option) -> String

    var body: some View {
        Menu {
            Picker("Сортировка", selection: $selection.animation(.snappy(duration: 0.25))) {
                ForEach(options) { option in
                    Label(title(option), systemImage: systemImage(option)).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityLabel("Сортировка: \(title(selection))")
    }
}

/// Операции в выбранном порядке: по дате — карточками дней, по сумме — одним списком.
struct SortedTransactionSections: View {
    let transactions: [Transaction]
    let folded: FoldedExchangeRateDifferences
    let sort: TransactionListSort

    var body: some View {
        switch sort {
        case .date:
            TransactionDaySections(transactions: transactions, folded: folded)
        case .amountDescending, .amountAscending:
            let sorted = sortedByAmount()
            Section {
                ForEach(sorted) { transaction in
                    NavigationLink {
                        TransactionDetailView(transaction: transaction)
                    } label: {
                        TransactionRowView(transaction: transaction, showsDate: true)
                    }
                }
            }
        }
    }

    /// Сумма в рублях вместе с курсовой разницей — как её видит аналитика.
    private func sortedByAmount() -> [Transaction] {
        let keyed = transactions.map { transaction -> (Transaction, Double) in
            let rub = folded.finalRubAmount(for: transaction) ?? transaction.rubAmount ?? transaction.amount
            return (transaction, rub)
        }
        let ordered = sort == .amountDescending
            ? keyed.sorted { $0.1 > $1.1 }
            : keyed.sorted { $0.1 < $1.1 }
        return ordered.map(\.0)
    }
}

extension View {
    /// Меню сортировки операций в панели навигации.
    func transactionSortToolbar(_ sort: Binding<TransactionListSort>) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SortMenu(
                    options: TransactionListSort.allCases,
                    selection: sort,
                    title: \.title,
                    systemImage: \.systemImage
                )
            }
        }
    }
}
