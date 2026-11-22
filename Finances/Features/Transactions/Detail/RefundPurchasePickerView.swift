//
//  RefundPurchasePickerView.swift
//  Finances
//
//  Выбор покупки, к которой относится возврат или компенсация.
//

import SwiftUI
import SwiftData

struct RefundPurchasePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let refund: Transaction

    @AllTransactions
    private var transactions: [Transaction]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @State private var searchText = ""

    /// Покупки до возврата не старше полугода: сначала того же магазина,
    /// потом те, что не меньше возврата, потом ближайшие по дате.
    private var candidates: [Transaction] {
        let earliest = Calendar.current.date(byAdding: .day, value: -RefundLinker.maxDaysBeforeRefund, to: refund.date) ?? .distantPast
        let latest = Calendar.current.date(byAdding: .day, value: 1, to: refund.date) ?? refund.date
        let query = searchText.trimmingCharacters(in: .whitespaces)

        return transactions
            .filter {
                $0.countsAsPurchaseInAnalytics && $0.date >= earliest && $0.date < latest &&
                (query.isEmpty || $0.details.localizedCaseInsensitiveContains(query))
            }
            .sorted { RefundLinker.score($0, for: refund) < RefundLinker.score($1, for: refund) }
            .prefix(100)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                if refund.refundOfLinkKey != nil {
                    Section {
                        Button("Отвязать от покупки", role: .destructive) {
                            refund.unlinkRefund()
                            try? modelContext.save()
                            dismiss()
                        }
                    }
                }

                Section {
                    if candidates.isEmpty {
                        Text("Нет покупок за полгода до возврата")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(candidates) { purchase in
                        Button {
                            refund.linkRefund(to: purchase)
                            try? modelContext.save()
                            dismiss()
                        } label: {
                            row(purchase)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Возврат уменьшит расходы в категории покупки и в её дне, а на счёте зачисление останется в день возврата.")
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Магазин или описание")
            .navigationTitle("Покупка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }

    private func row(_ purchase: Transaction) -> some View {
        let isLinked = purchase.linkKey != nil && purchase.linkKey == refund.refundOfLinkKey

        return HStack(spacing: 12) {
            AnalyticsCategoryIcon(category: CategoryLookup.findCategory(named: purchase.categoryName, in: categories))

            VStack(alignment: .leading, spacing: 2) {
                Text(purchase.details)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(purchase.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "ru_RU"))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(RefundLinker.formattedAmount(purchase))
                .monospacedDigit()
                .foregroundStyle(.primary)

            if isLinked {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Подбор покупки для возврата — и в выборе вручную, и при импорте выписки.
enum RefundLinker {
    static let maxDaysBeforeRefund = 180

    /// Меньше — правдоподобнее: тот же магазин, сумма не меньше возврата, ближе по дате.
    static func score(_ purchase: Transaction, for refund: Transaction) -> Double {
        let sameMerchant = ExchangeRateDifferenceMatcher.merchantKey(purchase.details)
            == ExchangeRateDifferenceMatcher.merchantKey(refund.details)
        let coversRefund = sameCurrency(purchase, refund) && purchase.amount + 0.005 >= refund.amount
        let days = abs(refund.date.timeIntervalSince(purchase.date)) / 86_400
        return (sameMerchant ? 0 : 10_000) + (coversRefund ? 0 : 1_000) + days
    }

    /// Покупка, к которой возврат можно привязать без вопросов: тот же магазин и
    /// валюта, сумма не меньше возврата, за полгода до него. Из нескольких — ближайшая.
    static func automaticPurchase(for refund: Transaction, among transactions: [Transaction]) -> Transaction? {
        let key = ExchangeRateDifferenceMatcher.merchantKey(refund.details)
        guard !key.isEmpty else { return nil }
        let earliest = Calendar.current.date(byAdding: .day, value: -maxDaysBeforeRefund, to: refund.date) ?? .distantPast

        return transactions
            .filter {
                $0.countsAsPurchaseInAnalytics && !$0.isAwaitingStatement &&
                $0.date >= earliest && $0.date <= refund.date &&
                sameCurrency($0, refund) && $0.amount + 0.005 >= refund.amount &&
                ExchangeRateDifferenceMatcher.merchantKey($0.details) == key
            }
            .max { $0.date < $1.date }
    }

    static func formattedAmount(_ transaction: Transaction) -> String {
        if let rub = transaction.rubAmount {
            return TagFormatting.rub(rub)
        }
        let symbol = CurrencyDisplay.symbol(for: transaction.currencyCode)
        return "\(transaction.amount.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "ru_RU")))) \(symbol)"
    }

    private static func sameCurrency(_ a: Transaction, _ b: Transaction) -> Bool {
        CurrencyDisplay.normalizedCode(from: a.currencyCode) == CurrencyDisplay.normalizedCode(from: b.currencyCode)
    }
}
