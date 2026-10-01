//
//  TransactionListByDateView.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import SwiftUI
import SwiftData

struct TransactionListByDateView: View {
    let date: Date

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    /// Курсовые разницы показываются под своими покупками, а не отдельной строкой.
    private var foldedDifferences: FoldedExchangeRateDifferences {
        ExchangeRateDifferenceMatcher.fold(transactions)
    }

    private func filteredTransactions(hiding hidden: Set<PersistentIdentifier>) -> [Transaction] {
        let calendar = Calendar.current
        return transactions.filter {
            !hidden.contains($0.persistentModelID) &&
            $0.countsAsExpenseInAnalytics &&
            calendar.isDate($0.date, inSameDayAs: date)
        }
    }

    var body: some View {
        let folded = foldedDifferences

        List {
            ForEach(filteredTransactions(hiding: folded.foldedIDs)) { transaction in
                NavigationLink {
                    TransactionDetailView(transaction: transaction)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        TransactionRowView(transaction: transaction)
                        ExchangeRateDifferenceCaption(purchase: transaction, folded: folded)
                    }
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle(formattedDate(date))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}