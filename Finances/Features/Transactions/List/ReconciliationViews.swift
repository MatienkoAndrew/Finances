//
//  ReconciliationViews.swift
//  Finances
//
//  Статус сверки под сводкой месяца и экран с пропусками и операциями,
//  которые требуют проверки.
//

import SwiftUI
import SwiftData

extension ReconciliationStatus {
    /// «Kaspi сверена по 18 ноября».
    var coverageLine: String {
        guard let coveredThrough else { return "Выписок Kaspi ещё нет" }
        return "Kaspi сверена по \(AnalyticsDateFormat.dayMonthLong.string(from: coveredThrough))"
    }

    /// Короткие пункты, требующие внимания: «3 оплаты Apple Pay ждут выписку».
    var attentionLines: [String] {
        var lines: [String] = []
        if !awaitingStatement.isEmpty {
            let count = awaitingStatement.count
            lines.append("\(count) \(Self.word(count, "оплата", "оплаты", "оплат")) Apple Pay \(count == 1 ? "ждёт" : "ждут") выписку")
        }
        if !gaps.isEmpty {
            lines.append("\(gaps.count) \(Self.word(gaps.count, "пропуск", "пропуска", "пропусков")) в выписках")
        }
        if !inconsistentStatements.isEmpty {
            let count = inconsistentStatements.count
            lines.append("\(count) \(Self.word(count, "выписка", "выписки", "выписок")) не \(count == 1 ? "сошлась" : "сошлись")")
        }
        if !pendingTags.isEmpty {
            let count = pendingTags.count
            lines.append("\(count) \(Self.word(count, "операция ждёт", "операции ждут", "операций ждут")) решения по метке")
        }
        return lines
    }

    static func word(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }

    static func dayRange(_ start: Date, _ end: Date) -> String {
        let calendar = KaspiStatementParser.calendar
        if calendar.isDate(start, inSameDayAs: end) {
            return AnalyticsDateFormat.dayMonthLong.string(from: start)
        }
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(AnalyticsDateFormat.day.string(from: start))–\(AnalyticsDateFormat.dayMonthLong.string(from: end))"
        }
        return "\(AnalyticsDateFormat.dayMonthLong.string(from: start)) – \(AnalyticsDateFormat.dayMonthLong.string(from: end))"
    }
}

/// Строка под сводкой месяца: по какой день сверено и что ждёт проверки.
struct ReconciliationStatusRow: View {
    let status: ReconciliationStatus

    private var iconName: String {
        if status.needsAttention { return "exclamationmark.circle.fill" }
        return status.coveredThrough == nil ? "doc.text.magnifyingglass" : "checkmark.seal.fill"
    }

    private var iconColor: Color {
        if status.needsAttention { return .orange }
        return status.coveredThrough == nil ? .secondary : .green
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.coverageLine)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                ForEach(status.attentionLines, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Пропущенные интервалы, несошедшиеся выписки и операции, требующие проверки.
struct ReconciliationDetailView: View {
    let status: ReconciliationStatus

    private let today: Date = {
        let calendar = KaspiStatementParser.calendar
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
    }()

    var body: some View {
        List {
            Section {
                Label(status.coverageLine, systemImage: "doc.text.magnifyingglass")
                if let coveredThrough = status.coveredThrough,
                   let nextDay = KaspiStatementParser.calendar.date(byAdding: .day, value: 1, to: coveredThrough),
                   nextDay <= today {
                    Text("Без выписки: \(ReconciliationStatus.dayRange(nextDay, today))")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Операции после последней выписки и в пропусках могут быть неполными — сравнение месяцев за эти дни приблизительное.")
            }

            if !status.gaps.isEmpty {
                Section("Пропуски между выписками") {
                    ForEach(status.gaps) { gap in
                        Label(ReconciliationStatus.dayRange(gap.start, gap.end), systemImage: "calendar.badge.exclamationmark")
                    }
                }
            }

            if !status.inconsistentStatements.isEmpty {
                Section("Итоги не сошлись") {
                    ForEach(status.inconsistentStatements) { coverage in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(coverage.fileName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(inconsistencyText(coverage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !status.awaitingStatement.isEmpty {
                Section("Apple Pay ждут выписку") {
                    ForEach(status.awaitingStatement) { transaction in
                        NavigationLink(value: transaction.persistentModelID) {
                            TransactionRowView(transaction: transaction, showsDate: true)
                        }
                    }
                }
            }

            if !status.pendingTags.isEmpty {
                Section("Ждут решения по метке") {
                    ForEach(status.pendingTags) { transaction in
                        NavigationLink(value: transaction.persistentModelID) {
                            TransactionRowView(transaction: transaction, showsDate: true)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Сверка")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func inconsistencyText(_ coverage: StatementCoverage) -> String {
        var parts: [String] = []
        if !coverage.mismatchedTypes.isEmpty {
            parts.append("не сошлись: \(coverage.mismatchedTypes.joined(separator: ", "))")
        }
        if coverage.unrecognizedLinesCount > 0 {
            parts.append("нераспознанных строк: \(coverage.unrecognizedLinesCount)")
        }
        let period = ReconciliationStatus.dayRange(coverage.periodStart, coverage.periodEnd)
        return "\(period) · " + parts.joined(separator: ", ")
    }
}
