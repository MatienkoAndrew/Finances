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
    /// Дни с операциями — точки в календаре.
    var activeDays: Set<Date> = []

    @State private var draft = TransactionFilter()
    /// Период в календаре: начало и конец (включительно); nil — всё время.
    @State private var rangeStart: Date?
    @State private var rangeEnd: Date?

    private var hasChanges: Bool {
        draft.isActive || rangeStart != nil
    }

    /// Быстрый выбор: этот и прошлый месяц.
    private func selectMonth(offset: Int) {
        let calendar = Calendar.current
        guard let base = calendar.date(byAdding: .month, value: offset, to: .now),
              let interval = calendar.dateInterval(of: .month, for: base),
              let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            rangeStart = interval.start
            rangeEnd = min(last, calendar.startOfDay(for: .now))
        }
    }

    private var rangeTitle: String {
        guard let rangeStart else { return "Всё время" }
        var filter = TransactionFilter()
        filter.period = .custom
        filter.customStart = rangeStart
        filter.customEnd = rangeEnd ?? rangeStart
        return filter.periodTitle()
    }

    private func apply() {
        var result = draft
        if let rangeStart {
            result.period = .custom
            result.customStart = rangeStart
            result.customEnd = rangeEnd ?? rangeStart
        } else {
            result.period = .all
        }
        filter = result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        presetButton("Всё время", isSelected: rangeStart == nil) {
                            withAnimation(.snappy(duration: 0.2)) {
                                rangeStart = nil
                                rangeEnd = nil
                            }
                        }
                        presetButton("Этот месяц", isSelected: false) { selectMonth(offset: 0) }
                        presetButton("Прошлый", isSelected: false) { selectMonth(offset: -1) }
                    }

                    RangeCalendarView(start: $rangeStart, end: $rangeEnd, activeDays: activeDays)
                } header: {
                    HStack {
                        Text("Период")
                        Spacer()
                        Text(rangeTitle)
                            .textCase(nil)
                            .foregroundStyle(Color.accentColor)
                    }
                } footer: {
                    Text("Коснись дня — начало периода, второго — конец. Касание названия месяца выбирает его целиком.")
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

                if hasChanges {
                    Section {
                        Button("Сбросить фильтры", role: .destructive) {
                            draft = TransactionFilter()
                            rangeStart = nil
                            rangeEnd = nil
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
                        apply()
                        dismiss()
                    }
                }
            }
            .onAppear {
                draft = filter
                if let interval = filter.dateInterval() {
                    rangeStart = interval.start
                    rangeEnd = Calendar.current.date(byAdding: .day, value: -1, to: interval.end)
                }
            }
        }
    }
}

private func presetButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
    }
    .buttonStyle(.plain)
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
