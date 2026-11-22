//
//  TripComparisonView.swift
//  Finances
//
//  Сравнение двух поездок (меток): полная стоимость, траты в день на месте
//  и разбивка по категориям.
//

import SwiftUI
import SwiftData

struct TripComparisonView: View {
    @AllTransactions
    private var transactions: [Transaction]

    @Environment(\.allTransactionsSnapshot) private var transactionsSnapshot

    @Query(sort: \TransactionTag.createdAt, order: .reverse)
    private var tags: [TransactionTag]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @Query
    private var settingsList: [AppSettings]

    @State private var firstName: String?
    @State private var secondName: String?

    /// Первая метка, с которой открыли сравнение.
    var initialTagName: String?

    private var first: TransactionTag? { tags.first { $0.name == firstName } }
    private var second: TransactionTag? { tags.first { $0.name == secondName } }

    var body: some View {
        let folded = FoldedDifferencesCache.current(transactionsSnapshot)
        let firstStats = first.flatMap { stats(for: $0, folded: folded) }
        let secondStats = second.flatMap { stats(for: $0, folded: folded) }

        List {
            Section {
                tagPicker("Первая", selection: $firstName, excluding: secondName)
                tagPicker("Вторая", selection: $secondName, excluding: firstName)
            }

            if let first, let second {
                Section {
                    header(first, second)
                    metricRow("Полная стоимость", firstStats?.totalRub, secondStats?.totalRub)
                    metricRow("В день на месте", firstStats?.perDayOnSite, secondStats?.perDayOnSite)
                    daysRow(firstStats, secondStats)
                    metricRow("На месте", firstStats?.onSiteRub, secondStats?.onSiteRub)
                    metricRow("До поездки", firstStats?.beforeRub, secondStats?.beforeRub)
                } footer: {
                    Text("Билеты и брони, купленные заранее, входят в полную стоимость, а траты в день считаются только за дни пребывания.")
                }

                let rows = categoryRows(firstStats, secondStats)
                if !rows.isEmpty {
                    Section("По категориям") {
                        ForEach(rows, id: \.name) { row in
                            categoryRow(row)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Сравнение поездок")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if firstName == nil {
                firstName = initialTagName ?? tags.first?.name
            }
            if secondName == nil {
                secondName = tags.first { $0.name != firstName }?.name
            }
        }
    }

    private func stats(for tag: TransactionTag, folded: FoldedExchangeRateDifferences) -> TripStats? {
        TripStats.make(
            tag: tag,
            transactions: transactions,
            settings: settingsList.first,
            trackedRates: trackedRates,
            folded: folded
        )
    }

    private func tagPicker(_ title: String, selection: Binding<String?>, excluding other: String?) -> some View {
        Picker(title, selection: selection) {
            Text("Не выбрана").tag(nil as String?)
            ForEach(tags.filter { $0.name != other }) { tag in
                Text(tag.name).tag(Optional(tag.name))
            }
        }
    }

    private func header(_ first: TransactionTag, _ second: TransactionTag) -> some View {
        HStack {
            Text("")
                .frame(maxWidth: .infinity, alignment: .leading)
            tagTitle(first)
            tagTitle(second)
        }
    }

    private func tagTitle(_ tag: TransactionTag) -> some View {
        HStack(spacing: 4) {
            TagIconView(icon: tag.icon, colorHex: tag.colorHex, size: 20)
            Text(tag.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(width: 104, alignment: .trailing)
    }

    private func metricRow(_ title: String, _ first: Double?, _ second: Double?) -> some View {
        HStack {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            valueCell(first.map(TagFormatting.rub), highlight: isLower(first, than: second))
            valueCell(second.map(TagFormatting.rub), highlight: isLower(second, than: first))
        }
    }

    private func daysRow(_ first: TripStats?, _ second: TripStats?) -> some View {
        HStack {
            Text("Дней на месте")
                .frame(maxWidth: .infinity, alignment: .leading)
            valueCell(first.map { "\($0.stayDays)" }, highlight: false)
            valueCell(second.map { "\($0.stayDays)" }, highlight: false)
        }
    }

    private func valueCell(_ text: String?, highlight: Bool) -> some View {
        Text(text ?? "—")
            .font(.subheadline.weight(highlight ? .semibold : .regular))
            .foregroundStyle(highlight ? Color.green : Color.primary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 104, alignment: .trailing)
    }

    /// Меньшая трата подсвечивается, когда обе есть и заметно отличаются.
    private func isLower(_ value: Double?, than other: Double?) -> Bool {
        guard let value, let other, value > 0, other > 0 else { return false }
        return value < other * 0.995
    }

    private struct CategoryRow {
        let name: String
        let first: Double
        let second: Double
    }

    private func categoryRows(_ first: TripStats?, _ second: TripStats?) -> [CategoryRow] {
        let firstTotals = Dictionary((first?.categories ?? []).map { ($0.category, $0.total) }, uniquingKeysWith: +)
        let secondTotals = Dictionary((second?.categories ?? []).map { ($0.category, $0.total) }, uniquingKeysWith: +)
        return Set(firstTotals.keys).union(secondTotals.keys)
            .map { CategoryRow(name: $0, first: firstTotals[$0] ?? 0, second: secondTotals[$0] ?? 0) }
            .sorted { max($0.first, $0.second) > max($1.first, $1.second) }
    }

    private func categoryRow(_ row: CategoryRow) -> some View {
        HStack(spacing: 10) {
            AnalyticsCategoryIcon(category: CategoryLookup.findCategory(named: row.name, in: categories), size: 26)
            Text(row.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            valueCell(row.first > 0 ? TagFormatting.rub(row.first) : nil, highlight: isLower(row.first, than: row.second))
            valueCell(row.second > 0 ? TagFormatting.rub(row.second) : nil, highlight: isLower(row.second, than: row.first))
        }
    }
}
