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

    @AllTransactions
    private var transactions: [Transaction]

    /// Курсовые разницы показываются под своими покупками, а не отдельной строкой.
    private var foldedDifferences: FoldedExchangeRateDifferences {
        ExchangeRateDifferenceMatcher.fold(transactions)
    }

    private func filteredTransactions(hiding hidden: Set<PersistentIdentifier>) -> [Transaction] {
        transactions.filter {
            !hidden.contains($0.persistentModelID) &&
            $0.countsAsExpenseInAnalytics &&
            normalizedMerchantName($0.details) == merchantTitle &&
            scope.matches($0)
        }
    }

    var body: some View {
        let folded = foldedDifferences

        List {
            TransactionDaySections(
                transactions: filteredTransactions(hiding: folded.foldedIDs),
                folded: folded
            )
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
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