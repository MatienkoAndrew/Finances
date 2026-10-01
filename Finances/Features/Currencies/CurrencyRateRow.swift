//
//  CurrencyRateRow.swift
//  Finances
//
//  Строка валюты в настройках: флаг, код, название и курс в понятном виде —
//  «1 000 VND = 3,20 ₽», с изменением к прошлому курсу ЦБ и датой курса.
//

import SwiftUI

struct CurrencyRateRow: View {
    let rate: TrackedExchangeRate
    /// Последний курс по дням и предыдущий; nil — курса ещё нет.
    let latest: (rubPerUnit: Double, day: Date, previous: Double?)?

    private static let locale = Locale(identifier: "ru_RU")

    var body: some View {
        HStack(spacing: 12) {
            Text(rate.flag)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(rate.code)
                    .font(.headline)
                Text(SupportedCurrency.byCode(rate.code).name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if let latest, latest.rubPerUnit > 0 {
                    Text(Self.rateLine(code: rate.code, rubPerUnit: latest.rubPerUnit))
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                    if let detail = detail(latest) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } else {
                    Text("нет курса")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            // Курс всегда в одну строку — сжимается название слева.
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// «▲ 0,42 % · на 2 окт.» — изменение к прошлому курсу и дата курса.
    private func detail(_ latest: (rubPerUnit: Double, day: Date, previous: Double?)) -> String? {
        var parts: [String] = []
        if let change = Self.changeText(latest) {
            parts.append(change)
        }
        if latest.day > .distantPast {
            parts.append("на \(latest.day.formatted(.dateTime.day().month(.abbreviated).locale(Self.locale)))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// «▲ 0,42 %» — изменение к прошлому курсу; nil, если курс не менялся.
    static func changeText(_ latest: (rubPerUnit: Double, day: Date, previous: Double?)) -> String? {
        guard let previous = latest.previous, previous > 0 else { return nil }
        let change = (latest.rubPerUnit - previous) / previous
        guard abs(change) >= 0.0001 else { return nil }
        let arrow = change > 0 ? "▲" : "▼"
        return "\(arrow) \(abs(change).formatted(.percent.precision(.fractionLength(2)).locale(locale)))"
    }

    /// Столько единиц валюты, чтобы в рублях вышло не меньше рубля:
    /// «1 USD = 81,20 ₽», «10 KZT = 1,91 ₽», «1 000 VND = 3,20 ₽».
    static func rateLine(code: String, rubPerUnit: Double) -> String {
        var units = 1.0
        while rubPerUnit * units < 1, units < 1_000_000 {
            units *= 10
        }
        let unitsText = units.formatted(.number.precision(.fractionLength(0)).locale(locale))
        let rubText = (rubPerUnit * units).formatted(.number.precision(.fractionLength(2)).locale(locale))
        return "\(unitsText) \(code) = \(rubText) ₽"
    }
}

/// Плитка курса для ленты в настройках: флаг, код, курс и изменение.
struct CurrencyRateTile: View {
    let rate: TrackedExchangeRate
    let latest: (rubPerUnit: Double, day: Date, previous: Double?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(rate.flag)
                    .font(.title2)
                Spacer(minLength: 12)
                Text(rate.code)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let latest, latest.rubPerUnit > 0 {
                    Text(CurrencyRateRow.rateLine(code: rate.code, rubPerUnit: latest.rubPerUnit))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(CurrencyRateRow.changeText(latest) ?? "без изменений")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("нет курса")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(" ")
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 128, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
