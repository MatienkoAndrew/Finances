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
    /// Только эта подкатегория (плитка в аналитике); nil — вся категория.
    var subcategoryTitle: String? = nil
    let scope: AnalyticsScope

    @AllTransactions
    private var transactions: [Transaction]

    @Environment(\.allTransactionsSnapshot) private var transactionsSnapshot

    @AppStorage(TransactionListSort.storageKey) private var sort: TransactionListSort = .date

    /// Курсовые разницы, привязанные к своим покупкам, отдельной строкой не показываются.
    private var foldedDifferences: FoldedExchangeRateDifferences {
        FoldedDifferencesCache.current(transactionsSnapshot)
    }

    private func filteredTransactions(hiding hidden: Set<PersistentIdentifier>) -> [Transaction] {
        transactions.filter {
            !hidden.contains($0.persistentModelID) &&
            $0.countsAsExpenseInAnalytics &&
            CategoryTotalsAccumulator.categoryName(of: $0) == categoryTitle &&
            (subcategoryTitle == nil || CategoryTotalsAccumulator.subcategoryName(of: $0) == subcategoryTitle) &&
            scope.matches($0)
        }
    }

    var body: some View {
        let folded = foldedDifferences

        List {
            SortedTransactionSections(
                transactions: filteredTransactions(hiding: folded.foldedIDs),
                folded: folded,
                sort: sort
            )
        }
        .transactionSortToolbar($sort)
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle(subcategoryTitle.map { "\(categoryTitle) · \($0)" } ?? categoryTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}