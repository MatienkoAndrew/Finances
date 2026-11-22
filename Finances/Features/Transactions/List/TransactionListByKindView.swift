//
//  TransactionListByKindView.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import SwiftUI
import SwiftData

struct TransactionListByKindView: View {
    let kind: TransactionKind
    let scope: AnalyticsScope

    @AllTransactions
    private var transactions: [Transaction]

    @Environment(\.allTransactionsSnapshot) private var transactionsSnapshot

    @AppStorage(TransactionListSort.storageKey) private var sort: TransactionListSort = .date

    /// Курсовые разницы, привязанные к своим покупкам, отдельной строкой не показываются.
    private var foldedDifferences: FoldedExchangeRateDifferences {
        FoldedDifferencesCache.current(transactionsSnapshot)
    }

    /// Как в аналитике: в расходах — и оплаты переводом, и возвраты, в доходах — без них.
    private func matchesKind(_ transaction: Transaction) -> Bool {
        switch kind {
        case .expense: return transaction.countsAsExpenseInAnalytics
        case .income: return transaction.countsAsIncomeInAnalytics
        case .transfer: return transaction.kind == .transfer
        }
    }

    private func filteredTransactions(hiding hidden: Set<PersistentIdentifier>) -> [Transaction] {
        transactions.filter {
            !hidden.contains($0.persistentModelID) && matchesKind($0) && scope.matches($0)
        }
    }

    var body: some View {
        let folded = foldedDifferences
        let visible = filteredTransactions(hiding: folded.foldedIDs)

        List {
            SortedTransactionSections(transactions: visible, folded: folded, sort: sort)
        }
        .transactionSortToolbar($sort)
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            HStack {
                Text(scope.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(visible.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }
}