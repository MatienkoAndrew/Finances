//
//  CurrencyRatesView.swift
//  Finances
//
//  Все валюты и курсы: список, добавление, удаление, обновление
//  (кнопкой или потянув вниз). В настройках — только превью этого экрана.
//

import SwiftUI
import SwiftData

struct CurrencyRatesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @Query(sort: \DailyExchangeRate.day, order: .forward)
    private var dailyRates: [DailyExchangeRate]

    @Query
    private var transactions: [Transaction]

    @State private var isShowingAddCurrency = false

    private var rateSync: ExchangeRateSync { .shared }

    var body: some View {
        let counts = CurrencyRatesSummary.operationCounts(transactions)
        let rateTable = RubRateTable(rates: dailyRates)
        let displayedRates = CurrencyRatesSummary.sorted(trackedRates, by: counts)

        List {
            Section {
                ForEach(displayedRates) { rate in
                    let code = CurrencyDisplay.normalizedCode(from: rate.code)
                    CurrencyRateRow(rate: rate, latest: rateTable.latest(code))
                        // Валюты из операций всё равно вернутся в список.
                        .deleteDisabled((counts[code] ?? 0) > 0)
                }
                .onDelete { offsets in
                    for rate in offsets.map({ displayedRates[$0] }) {
                        modelContext.delete(rate)
                    }
                    try? modelContext.save()
                }
            } footer: {
                Text(CurrencyRatesSummary.footer(rateSync))
            }

            Section {
                Button {
                    isShowingAddCurrency = true
                } label: {
                    Label("Добавить валюту", systemImage: "plus")
                }

                Button {
                    Task { await rateSync.run(context: modelContext) }
                } label: {
                    HStack {
                        Label(rateSync.isRunning ? "Обновляем курсы…" : "Обновить курсы", systemImage: "arrow.clockwise")
                        Spacer()
                        if rateSync.isRunning {
                            ProgressView()
                        }
                    }
                }
                .disabled(rateSync.isRunning)
            }
        }
        .navigationTitle("Валюты и курсы")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await rateSync.run(context: modelContext)
        }
        .sheet(isPresented: $isShowingAddCurrency) {
            AddTrackedCurrencyView()
        }
    }
}

/// Общее для экрана валют и карточки курсов в настройках.
enum CurrencyRatesSummary {
    /// Сколько операций в каждой валюте.
    static func operationCounts(_ transactions: [Transaction]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for transaction in transactions {
            counts[CurrencyDisplay.normalizedCode(from: transaction.currencyCode), default: 0] += 1
        }
        return counts
    }

    /// Сначала валюты, в которых больше всего операций, потом остальные по коду.
    static func sorted(_ rates: [TrackedExchangeRate], by counts: [String: Int]) -> [TrackedExchangeRate] {
        rates.sorted { lhs, rhs in
            let left = counts[CurrencyDisplay.normalizedCode(from: lhs.code)] ?? 0
            let right = counts[CurrencyDisplay.normalizedCode(from: rhs.code)] ?? 0
            if left != right { return left > right }
            return lhs.code < rhs.code
        }
    }

    /// Откуда курсы, как считаются рубли и когда обновлялись.
    @MainActor
    static func footer(_ sync: ExchangeRateSync) -> String {
        if let error = sync.lastError { return error }
        var text = "Курсы ЦБ РФ, для валют, которых у ЦБ нет, — открытый currency-api. Рубли у каждой операции считаются по курсу на её дату."
        if let updated = sync.lastUpdated {
            text += " Обновлено \(updatedText(updated))."
        }
        return text
    }

    /// «сегодня в 21:03», «вчера в 9:12», «28 сентября в 9:12».
    static func updatedText(_ date: Date) -> String {
        let locale = Locale(identifier: "ru_RU")
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        if calendar.isDateInToday(date) { return "сегодня в \(time)" }
        if calendar.isDateInYesterday(date) { return "вчера в \(time)" }
        return "\(date.formatted(.dateTime.day().month(.wide).locale(locale))) в \(time)"
    }
}
