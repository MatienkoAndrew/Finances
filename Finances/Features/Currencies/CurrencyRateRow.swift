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
        if let previous = latest.previous, previous > 0 {
            let change = (latest.rubPerUnit - previous) / previous
            if abs(change) >= 0.0001 {
                let arrow = change > 0 ? "▲" : "▼"
                parts.append("\(arrow) \(abs(change).formatted(.percent.precision(.fractionLength(2)).locale(Self.locale)))")
            }
        }
        if latest.day > .distantPast {
            parts.append("на \(latest.day.formatted(.dateTime.day().month(.abbreviated).locale(Self.locale)))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
