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

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    /// Курсовые разницы показываются под своими покупками, а не отдельной строкой.
    private var foldedDifferences: FoldedExchangeRateDifferences {
        ExchangeRateDifferenceMatcher.fold(transactions)
    }

    private func filteredTransactions(hiding hidden: Set<PersistentIdentifier>) -> [Transaction] {
        transactions.filter {
            !hidden.contains($0.persistentModelID) && $0.kind == kind && scope.matches($0)
        }
    }

    var body: some View {
        let folded = foldedDifferences
        let visible = filteredTransactions(hiding: folded.foldedIDs)

        List {
            ForEach(visible) { transaction in
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