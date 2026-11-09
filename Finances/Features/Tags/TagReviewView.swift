//
//  TagReviewView.swift
//  Finances
//
//  Расходы за даты поездки, оплаченные не в её валюте (доллары в Японии,
//  комиссия в тенге): пользователь решает, относятся ли они к метке.
//

import SwiftUI
import SwiftData

struct TagReviewView: View {
    @Environment(\.modelContext) private var modelContext

    let tag: TransactionTag

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    private var pending: [Transaction] {
        transactions.filter { $0.isTagPending(tag.name) }
    }

    private var currenciesText: String {
        tag.tripCurrencyCodes.sorted().joined(separator: ", ")
    }

    var body: some View {
        let pending = pending

        List {
            if pending.isEmpty {
                ContentUnavailableView(
                    "Всё разобрано",
                    systemImage: "checkmark.circle",
                    description: Text("Новые расходы за даты поездки не в \(currenciesText) появятся здесь.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(pending) { transaction in
                        row(for: transaction)
                    }
                } footer: {
                    Text("Расходы за даты «\(tag.name)», оплаченные не в \(currenciesText). Отметь, какие из них относятся к поездке.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("На рассмотрении")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !pending.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Все") {
                        Button {
                            decideAll(pending, include: true)
                        } label: {
                            Label("Все — «\(tag.name)»", systemImage: "checkmark")
                        }

                        Button(role: .destructive) {
                            decideAll(pending, include: false)
                        } label: {
                            Label("Все — не «\(tag.name)»", systemImage: "xmark")
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: pending.count)
    }

    private func row(for transaction: Transaction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TransactionRowView(transaction: transaction, showsDate: true, hiddenTagNames: [tag.name])

            HStack(spacing: 8) {
                Button {
                    decide(transaction, include: true)
                } label: {
                    decisionLabel(tag.name, systemImage: "checkmark")
                }
                .tint(.green)

                Button {
                    decide(transaction, include: false)
                } label: {
                    decisionLabel("Не \(tag.name)", systemImage: "xmark")
                }
                .tint(.secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                decide(transaction, include: true)
            } label: {
                Label(tag.name, systemImage: "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                decide(transaction, include: false)
            } label: {
                Label("Не \(tag.name)", systemImage: "xmark")
            }
            .tint(.gray)
        }
    }

    /// Подпись кнопки: иконка того же цвета, что и текст (иначе она остаётся синей).
    private func decisionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// Решение пользователя — ручное: правило валюты его уже не перетрёт.
    private func decide(_ transaction: Transaction, include: Bool) {
        withAnimation(.snappy(duration: 0.25)) {
            apply(include, to: transaction)
        }
        try? modelContext.save()
    }

    private func decideAll(_ transactions: [Transaction], include: Bool) {
        withAnimation(.snappy(duration: 0.25)) {
            for transaction in transactions {
                apply(include, to: transaction)
            }
        }
        try? modelContext.save()
    }

    private func apply(_ include: Bool, to transaction: Transaction) {
        if include {
            transaction.addTag(tag.name, manual: true)
        } else {
            transaction.removeTag(tag.name, manual: true)
        }
    }
}
