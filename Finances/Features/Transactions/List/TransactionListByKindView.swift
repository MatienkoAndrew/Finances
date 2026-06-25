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

    private var filteredTransactions: [Transaction] {
        transactions.filter {
            $0.kind == kind && scope.contains($0.date)
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
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            HStack {
                Text(scope.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(filteredTransactions.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }
}