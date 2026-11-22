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

    @AllTransactions
    private var transactions: [Transaction]

    // Курсы обновляются в фоне — подписка, чтобы рублёвый эквивалент пересчитался.
    @Query private var trackedRates: [TrackedExchangeRate]
    /// Курсы — общим снимком: он обновляется сам, когда сохраняются курсы.
    private var rateStore = RubRateTableStore.shared
    @Environment(\.allTransactionsSnapshot) private var transactionsSnapshot

    @State private var isShowingAddAccount = false

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    private var archivedAccounts: [Account] {
        accounts.filter(\.isArchived)
    }

    var body: some View {
        let balances = AccountBalanceCalculator.cachedBalances(transactionsSnapshot)
        let rubRates = rateStore.table

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if activeAccounts.isEmpty {
                        emptyState
                    } else {
                        totalCard(balances, rubRates: rubRates)

                        activeSection(balances, rubRates: rubRates)

                        if !archivedAccounts.isEmpty {
                            archivedSection(balances, rubRates: rubRates)
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

    private func activeSection(_ balances: [PersistentIdentifier: Double], rubRates: RubRateTable) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Активные")
                .font(.title3.bold())

            ForEach(activeAccounts) { account in
                NavigationLink {
                    AccountDetailView(account: account)
                } label: {
                    AccountRowView(
                        account: account,
                        balance: balances[account.persistentModelID] ?? 0,
                        rubEquivalent: rubEquivalent(
                            of: balances[account.persistentModelID] ?? 0,
                            account: account,
                            rubRates: rubRates
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func archivedSection(_ balances: [PersistentIdentifier: Double], rubRates: RubRateTable) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Архив")
                .font(.title3.bold())

            ForEach(archivedAccounts) { account in
                NavigationLink {
                    AccountDetailView(account: account)
                } label: {
                    AccountRowView(
                        account: account,
                        balance: balances[account.persistentModelID] ?? 0,
                        rubEquivalent: rubEquivalent(
                            of: balances[account.persistentModelID] ?? 0,
                            account: account,
                            rubRates: rubRates
                        )
                    )
                    .opacity(0.7)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Баланс в рублях по последнему известному курсу (знак сохраняется).
    private func rubEquivalent(of balance: Double, account: Account, rubRates: RubRateTable) -> Double? {
        let code = CurrencyDisplay.normalizedCode(from: account.currencyCode)
        guard code != "RUB", let rate = rubRates.latest(code)?.rubPerUnit, rate > 0 else {
            return nil
        }
        return balance * rate
    }

    /// Сумма активных счетов в рублях. Счета без курса в сумму не входят.
    private func totalCard(_ balances: [PersistentIdentifier: Double], rubRates: RubRateTable) -> some View {
        var total = 0.0
        var skipped: [String] = []
        for account in activeAccounts {
            let balance = balances[account.persistentModelID] ?? 0
            let code = CurrencyDisplay.normalizedCode(from: account.currencyCode)
            if code == "RUB" {
                total += balance
            } else if let rub = rubEquivalent(of: balance, account: account, rubRates: rubRates) {
                total += rub
            } else if balance != 0 {
                skipped.append(account.name)
            }
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text("Всего в рублях")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("≈ \(Self.formattedRub(total))")
                .font(.title.bold())
                .foregroundStyle(total < 0 ? .red : .primary)

            if !skipped.isEmpty {
                Text("Без курса, не учтены: \(skipped.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private static let rubFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","
        return formatter
    }()

    private static func formattedRub(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        let number = rubFormatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        return "\(sign)\(number) ₽"
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
