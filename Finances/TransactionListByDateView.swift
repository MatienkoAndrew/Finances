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

    private var filteredTransactions: [Transaction] {
        let calendar = Calendar.current
        return transactions.filter {
            $0.countsAsExpenseInAnalytics &&
            calendar.isDate($0.date, inSameDayAs: date)
        }
    }

    var body: some View {
        List {
            ForEach(filteredTransactions) { transaction in
                NavigationLink {
                    TransactionDetailView(transaction: transaction)
                } label: {
                    TransactionRowView(transaction: transaction)
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