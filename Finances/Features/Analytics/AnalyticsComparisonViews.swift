//
//  AnalyticsComparisonViews.swift
//  Finances
//
//  Карточка «Что изменилось» и экраны сравнения категорий по двум отрезкам.
//

import SwiftUI

enum ComparisonFormat {
    /// «+1 200 ₽», «−800 ₽».
    static func signedRub(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "−"
        return "\(sign)\(TagFormatting.rub(abs(value)))"
    }

    /// Рост трат — красный, снижение — зелёный.
    static func color(for delta: Double) -> Color {
        delta > 0 ? .red : .green
    }

    static func purchases(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "покупка" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "покупки" }
        return "покупок"
    }
}

/// Карточка под шапкой периода: общая разница и три категории, которые её объясняют.
struct AnalyticsComparisonCard: View {
    let comparison: AnalyticsPeriodComparison
    let categoryItem: (String) -> ExpenseCategoryItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(comparison.current.title) против \(comparison.previous.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ComparisonFormat.signedRub(comparison.delta))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(ComparisonFormat.color(for: comparison.delta))
                        Text("\(TagFormatting.rub(comparison.currentTotal)) против \(TagFormatting.rub(comparison.previousTotal))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 8)

                    if let fraction = comparison.deltaFraction, abs(fraction) >= 0.005 {
                        AnalyticsTrendBadge(delta: fraction)
                    }
                }
            }
            .padding(16)

            if comparison.topChanges.isEmpty {
                SettingsDivider()
                Text("По категориям траты не изменились")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ForEach(comparison.topChanges) { change in
                    SettingsDivider()
                    NavigationLink {
                        AnalyticsCategoryComparisonView(
                            change: change,
                            comparison: comparison,
                            category: categoryItem(change.category)
                        )
                    } label: {
                        AnalyticsCategoryChangeRow(change: change, category: categoryItem(change.category))
                    }
                    .buttonStyle(.plain)
                }

                if comparison.changes.count > comparison.topChanges.count {
                    SettingsDivider()
                    NavigationLink {
                        AnalyticsAllChangesView(comparison: comparison, categoryItem: categoryItem)
                    } label: {
                        HStack {
                            Text("Все категории · \(comparison.changes.count)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Строка категории: разница в ₽, покупки и средний чек «было → стало».
struct AnalyticsCategoryChangeRow: View {
    let change: AnalyticsCategoryChange
    let category: ExpenseCategoryItem?

    var body: some View {
        HStack(spacing: 14) {
            AnalyticsCategoryIcon(category: category)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(change.category)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(ComparisonFormat.signedRub(change.delta))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(ComparisonFormat.color(for: change.delta))
                        .fixedSize()
                }

                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var detailLine: String {
        let count = "\(change.previous.count) → \(change.current.count) \(ComparisonFormat.purchases(change.current.count))"
        let average = "ср. чек \(averageText(change.previous)) → \(averageText(change.current))"
        return "\(count) · \(average)"
    }

    private func averageText(_ total: AnalyticsCategoryPeriodTotal) -> String {
        total.count > 0 ? TagFormatting.rub(total.averageCheck) : "—"
    }
}

/// Все категории с изменением — по убыванию влияния.
struct AnalyticsAllChangesView: View {
    let comparison: AnalyticsPeriodComparison
    let categoryItem: (String) -> ExpenseCategoryItem?

    var body: some View {
        List {
            Section {
                ForEach(comparison.changes) { change in
                    NavigationLink {
                        AnalyticsCategoryComparisonView(
                            change: change,
                            comparison: comparison,
                            category: categoryItem(change.category)
                        )
                    } label: {
                        AnalyticsCategoryChangeRow(change: change, category: categoryItem(change.category))
                            .padding(.horizontal, -16)
                    }
                }
            } header: {
                Text("\(comparison.current.title) против \(comparison.previous.title)")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Что изменилось")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Категория в двух отрезках: суммы, покупки, средний чек и переход к операциям.
struct AnalyticsCategoryComparisonView: View {
    let change: AnalyticsCategoryChange
    let comparison: AnalyticsPeriodComparison
    let category: ExpenseCategoryItem?

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AnalyticsCategoryIcon(category: category, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ComparisonFormat.signedRub(change.delta))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(ComparisonFormat.color(for: change.delta))
                        Text(shareLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            periodSection(comparison.current, total: change.current)
            periodSection(comparison.previous, total: change.previous)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(change.category)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Какую часть общей разницы объясняет категория.
    private var shareLine: String {
        let total = comparison.delta
        guard abs(total) >= 0.005 else { return "Общие траты не изменились" }
        let share = change.delta / total
        return "\(share.formatted(.percent.precision(.fractionLength(0)))) общей разницы"
    }

    private func periodSection(_ range: AnalyticsComparisonRange, total: AnalyticsCategoryPeriodTotal) -> some View {
        Section(range.title) {
            LabeledContent("Сумма", value: TagFormatting.rub(total.total))
            LabeledContent("Покупок", value: "\(total.count)")
            LabeledContent("Средний чек", value: total.count > 0 ? TagFormatting.rub(total.averageCheck) : "—")
            if total.count > 0 {
                NavigationLink("Операции") {
                    TransactionListByCategoryView(
                        categoryTitle: change.category,
                        scope: comparison.scope(for: range)
                    )
                }
            }
        }
        .monospacedDigit()
    }
}
