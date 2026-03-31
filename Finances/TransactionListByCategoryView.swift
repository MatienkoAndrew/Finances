//
//  TransactionListByCategoryView.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import SwiftUI
import SwiftData

struct TransactionListByCategoryView: View {
    let categoryTitle: String
    let scope: AnalyticsScope

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    private var filteredTransactions: [Transaction] {
        transactions.filter {
            $0.countsAsExpenseInAnalytics &&
            ($0.categoryName ?? "Без категории") == categoryTitle &&
            scope.contains($0.date)
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
        .navigationTitle(categoryTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}