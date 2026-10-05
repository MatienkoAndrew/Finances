//
//  AccountsView.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \Expense.createdAt, order: .forward)
    private var legacyExpenses: [Expense]

    @Query(sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @State private var isShowingAddAccount = false

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    private var archivedAccounts: [Account] {
        accounts.filter(\.isArchived)
    }

    var body: some View {
        let balances = AccountBalanceCalculator.balances(transactions: transactions)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if activeAccounts.isEmpty {
                        emptyState
                    } else {
                        activeSection(balances)

                        if !archivedAccounts.isEmpty {
                            archivedSection(balances)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Счета")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddAccount = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddAccount) {
                AddAccountView()
            }
            .task(id: accounts.count) {
                DefaultAccountsSeeder.seedIfNeeded(
                    existingAccounts: accounts,
                    modelContext: modelContext
                )

                LegacyExpenseMigrator.migrateIfNeeded(
                    expenses: legacyExpenses,
                    existingTransactions: transactions,
                    accounts: accounts,
                    modelContext: modelContext
                )
            }
        }
    }

    private func activeSection(_ balances: [PersistentIdentifier: Double]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Активные")
                .font(.title3.bold())

            ForEach(activeAccounts) { account in
                NavigationLink {
                    AccountDetailView(account: account)
                } label: {
                    AccountRowView(
                        account: account,
                        balance: balances[account.persistentModelID] ?? 0
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func archivedSection(_ balances: [PersistentIdentifier: Double]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Архив")
                .font(.title3.bold())

            ForEach(archivedAccounts) { account in
                NavigationLink {
                    AccountDetailView(account: account)
                } label: {
                    AccountRowView(
                        account: account,
                        balance: balances[account.persistentModelID] ?? 0
                    )
                    .opacity(0.7)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wallet.bifold")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Пока нет счетов")
                .font(.headline)

            Text("Добавь счет или дождись автоматического создания дефолтных счетов")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Добавить счет") {
                isShowingAddAccount = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
