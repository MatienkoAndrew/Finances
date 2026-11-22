//
//  TransactionFilterViews.swift
//  Finances
//
//  Выбор фильтра, полоска активных фильтров и итог выборки.
//

import SwiftUI
import SwiftData

struct TransactionFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var filter: TransactionFilter
    let accounts: [Account]
    let categories: [ExpenseCategoryItem]
    let tags: [TransactionTag]
    let currencies: [String]

    @State private var draft = TransactionFilter()

    var body: some View {
        NavigationStack {
            Form {
                Section("Период") {
                    Picker("Период", selection: $draft.period) {
                        ForEach(TransactionFilter.Period.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    if draft.period == .custom {
                        DatePicker("С", selection: $draft.customStart, displayedComponents: .date)
                        DatePicker("По", selection: $draft.customEnd, displayedComponents: .date)
                    }
                }

                Section {
                    Picker("Счёт", selection: $draft.accountID) {
                        Text("Любой").tag(nil as PersistentIdentifier?)
                        ForEach(accounts) { account in
                            Text(account.displayTitle).tag(Optional(account.persistentModelID))
                        }
                    }

                    Picker("Категория", selection: $draft.categoryName) {
                        Text("Любая").tag(nil as String?)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.name))
                        }
                        Text(CategoryTotalsAccumulator.uncategorized).tag(Optional(CategoryTotalsAccumulator.uncategorized))
                    }

                    if !tags.isEmpty {
                        Picker("Метка", selection: $draft.tagName) {
                            Text("Любая").tag(nil as String?)
                            ForEach(tags) { tag in
                                Text(tag.name).tag(Optional(tag.name))
                            }
                        }
                    }

                    Picker("Валюта покупки", selection: $draft.currencyCode) {
                        Text("Любая").tag(nil as String?)
                        ForEach(currencies, id: \.self) { code in
                            Text("\(code) · \(CurrencyDisplay.symbol(for: code))").tag(Optional(code))
                        }
                    }
                } footer: {
                    Text("Валюта покупки — валюта магазина: у оплаты картой в тенге за границей это валюта страны.")
                }

                if draft.isActive {
                    Section {
                        Button("Сбросить фильтры", role: .destructive) {
                            draft = TransactionFilter()
                        }
                    }
                }
            }
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        filter = draft
                        dismiss()
                    }
                }
            }
            .onAppear { draft = filter }
        }
    }
}

/// Активные фильтры капсулами: касание открывает выбор, крестик — снимает фильтр.
struct TransactionFilterChips: View {
    @Binding var filter: TransactionFilter
    let accounts: [Account]
    let onEdit: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if filter.period != .all {
                    chip(filter.periodTitle(), systemImage: "calendar") { filter.period = .all }
                }
                if let id = filter.accountID {
                    chip(accounts.first { $0.persistentModelID == id }?.displayTitle ?? "Счёт", systemImage: "creditcard") {
                        filter.accountID = nil
                    }
                }
                if let category = filter.categoryName {
                    chip(category, systemImage: "square.grid.2x2") { filter.categoryName = nil }
                }
                if let tag = filter.tagName {
                    chip(tag, systemImage: "tag") { filter.tagName = nil }
                }
                if let currency = filter.currencyCode {
                    chip(currency, systemImage: "coloncurrencysign.circle") { filter.currencyCode = nil }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, systemImage: String, onClear: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button(action: onEdit) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.snappy(duration: 0.2)) { onClear() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Снять фильтр \(title)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}

/// Сколько найдено и на какую сумму — по правилам аналитики.
struct TransactionFilterSummary: View {
    let totals: TransactionFilterTotals
    var showsAnalyticsLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Найдено: \(TagFormatting.operations(totals.count))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if showsAnalyticsLink {
                    HStack(spacing: 4) {
                        Text("Аналитика")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                AnalyticsMetricTile(value: TagFormatting.rub(totals.expensesRub), title: "расходы")
                AnalyticsMetricTile(value: TagFormatting.rub(totals.incomeRub), title: "доходы")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
