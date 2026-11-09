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
    @Environment(\.scenePhase) private var scenePhase

    let tag: TransactionTag

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    /// Решения, ещё не записанные в базу: true — «к метке», false — «не к метке».
    ///
    /// Каждая запись в базу перерисовывает все вкладки приложения (список операций,
    /// аналитику, экран метки) — на телефоне до ~2 с на одно касание. Поэтому
    /// касание только убирает строку, а в базу решения уходят разом: при уходе
    /// с экрана, при сворачивании приложения и по кнопке «Все».
    @State private var decisions: [PersistentIdentifier: Bool] = [:]

    private var pending: [Transaction] {
        transactions.filter { $0.isTagPending(tag.name) && decisions[$0.persistentModelID] == nil }
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
        .onDisappear(perform: saveDecisions)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveDecisions() }
        }
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

    /// Касание: строка сразу уходит, в базу решение запишется позже — вместе с остальными.
    private func decide(_ transaction: Transaction, include: Bool) {
        withAnimation(.snappy(duration: 0.25)) {
            decisions[transaction.persistentModelID] = include
        }
    }

    /// «Все» — решение для всех оставшихся сразу, и одна запись в базу.
    private func decideAll(_ transactions: [Transaction], include: Bool) {
        for transaction in transactions {
            decisions[transaction.persistentModelID] = include
        }
        saveDecisions()
    }

    /// Решения пользователя — ручные: правило валюты их уже не перетрёт.
    /// Без анимации: иначе каждый список в приложении анимирует свою перестройку.
    private func saveDecisions() {
        guard !decisions.isEmpty else { return }
        let byID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.persistentModelID, $0) })
        for (id, include) in decisions {
            guard let transaction = byID[id] else { continue }
            if include {
                transaction.addTag(tag.name, manual: true)
            } else {
                transaction.removeTag(tag.name, manual: true)
            }
        }
        decisions = [:]
        try? modelContext.save()
    }
}
