//
//  TransactionListByMerchantView.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import SwiftUI
import SwiftData

struct TransactionListByMerchantView: View {
    let merchantTitle: String
    let scope: AnalyticsScope

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    private var filteredTransactions: [Transaction] {
        transactions.filter {
            $0.countsAsExpenseInAnalytics &&
            normalizedMerchantName($0.details) == merchantTitle &&
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
        .navigationTitle(merchantTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func normalizedMerchantName(_ details: String) -> String {
        let uppercased = details.uppercased()

        if uppercased.hasPrefix("GRAB ") {
            return "GRAB"
        }

        if uppercased.hasPrefix("PAYOO MCDONALDS") {
            return "PAYOO MCDONALDS"
        }

        if uppercased.hasPrefix("OPENAI CHATGPT SUBSCR") {
            return "OPENAI CHATGPT SUBSCR"
        }

        if uppercased.hasPrefix("APPLE.COM BILL") {
            return "APPLE.COM BILL"
        }

        if uppercased.hasPrefix("VNPAY 43 FACTORY") {
            return "VNPAY 43 FACTORY"
        }

        if uppercased.hasPrefix("VNPAY XLIII COFFEE") {
            return "VNPAY XLIII COFFEE"
        }

        return uppercased
    }
}