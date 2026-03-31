//
//  AccountDetailView.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import SwiftUI
import SwiftData

struct AccountDetailView: View {
    let account: Account

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Transaction.date, order: .reverse)
    private var allTransactions: [Transaction]

    private var relatedTransactions: [Transaction] {
        allTransactions.filter { transaction in
            transaction.fromAccount?.persistentModelID == account.persistentModelID ||
            transaction.toAccount?.persistentModelID == account.persistentModelID
        }
    }

    private var balance: Double {
        AccountBalanceCalculator.balance(
            for: account,
            transactions: allTransactions
        )
    }

    var body: some View {
        List {
            Section("Счет") {
                detailRow(title: "Название", value: account.name)
                detailRow(title: "Тип", value: account.type.title)
                detailRow(title: "Валюта", value: account.currencyCode)
                detailRow(title: "Баланс", value: formattedAmount(balance, currency: account.currencyCode))

                if let note = account.note, !note.isEmpty {
                    detailRow(title: "Заметка", value: note)
                }
            }

            Section("Операции") {
                if relatedTransactions.isEmpty {
                    Text("Пока нет операций")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(relatedTransactions) { transaction in
                        NavigationLink {
                            TransactionDetailView(transaction: transaction)
                        } label: {
                            TransactionRowView(transaction: transaction)
                        }
                    }
                }
            }

            Section {
                Button(account.isArchived ? "Вернуть из архива" : "Отправить в архив") {
                    account.isArchived.toggle()
                    try? modelContext.save()
                }
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
        }
        .padding(.vertical, 2)
    }

    private func formattedAmount(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        let sign = value < 0 ? "-" : ""
        let number = formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        return "\(sign)\(number) \(currency)"
    }
}