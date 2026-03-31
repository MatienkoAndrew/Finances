import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query
    private var settingsList: [AppSettings]

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @State private var isUpdatingRate = false
    @State private var rateMessage: String?
    @State private var rateErrorMessage: String?

    @State private var isShowingAddCurrency = false

    @AppStorage("rates_last_refresh_at") private var lastRatesRefreshAt: Double = 0

    private var settings: AppSettings {
        if let existing = settingsList.first {
            return existing
        } else {
            let newSettings = AppSettings()
            modelContext.insert(newSettings)
            return newSettings
        }
    }

    private var displayedTrackedRates: [TrackedExchangeRate] {
        let preferredOrder = ["USD", "EUR", "CNY", "VND", "SGD"]

        return trackedRates.sorted { lhs, rhs in
            let li = preferredOrder.firstIndex(of: lhs.code.uppercased()) ?? Int.max
            let ri = preferredOrder.firstIndex(of: rhs.code.uppercased()) ?? Int.max

            if li != ri { return li < ri }
            return lhs.code < rhs.code
        }
    }

    private var shouldRefreshRates: Bool {
        let now = Date().timeIntervalSince1970
        return now - lastRatesRefreshAt > 60 * 60 * 24
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Валюты и курсы") {
//                    currencyRow(
//                        flag: "🇷🇺",
//                        code: "RUB",
//                        name: "Российский рубль",
//                        subtitle: "Базовая валюта аналитики"
//                    )

                    currencyRow(
                        flag: "🇰🇿",
                        code: "KZT",
                        name: "Казахстанский тенге",
                        subtitle: "1 KZT = \(rubPerKztString()) RUB"
                    )

                    ForEach(displayedTrackedRates) { rate in
                        currencyRow(
                            flag: rate.flag,
                            code: rate.code,
                            name: rate.displayName,
                            subtitle: "1 \(rate.code) = \(stringFromDouble(rate.rubPerUnit)) RUB"
                        )
                    }
                    .onDelete(perform: deleteTrackedRates)

                    Button {
                        isShowingAddCurrency = true
                    } label: {
                        Text("Добавить валюту")
                    }

                    Button {
                        Task {
                            await refreshRatesNow()
                        }
                    } label: {
                        HStack {
                            if isUpdatingRate {
                                ProgressView()
                            }
                            Text(isUpdatingRate ? "Обновляем..." : "Обновить курсы")
                        }
                    }
                    .disabled(isUpdatingRate)

//                    Text("Новые транзакции используют свежий курс. Старые транзакции сохраняют исторический ₽-эквивалент и не пересчитываются задним числом.")
//                        .font(.caption)
//                        .foregroundStyle(.secondary)
                }

                Section("Данные") {
                    NavigationLink("Управление категориями") {
                        CategoriesView()
                    }

                    NavigationLink("Правила категорий") {
                        RulesView()
                    }
                }
            }
            .navigationTitle("Настройки")
            .sheet(isPresented: $isShowingAddCurrency) {
                AddTrackedCurrencyView()
            }
            .task {
                let inserted = DefaultTrackedCurrenciesSeeder.seedMissing(
                    existingRates: trackedRates,
                    modelContext: modelContext
                )

                if shouldRefreshRates {
                    await refreshRatesNow(extraRates: inserted)
                }
            }
            .alert("Курсы обновлены", isPresented: Binding(
                get: { rateMessage != nil },
                set: { if !$0 { rateMessage = nil } }
            )) {
                Button("OK", role: .cancel) { rateMessage = nil }
            } message: {
                Text(rateMessage ?? "")
            }
            .alert("Ошибка обновления курсов", isPresented: Binding(
                get: { rateErrorMessage != nil },
                set: { if !$0 { rateErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { rateErrorMessage = nil }
            } message: {
                Text(rateErrorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func currencyRow(
        flag: String,
        code: String,
        name: String,
        subtitle: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(flag)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(code)
                        .font(.headline)

                    Text("— \(name)")
                        .font(.headline)
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func rubPerKztString() -> String {
        guard settings.kztPerRub > 0 else { return "0" }
        return stringFromDouble(1 / settings.kztPerRub)
    }

    @MainActor
    private func refreshRatesNow(extraRates: [TrackedExchangeRate] = []) async {
        isUpdatingRate = true
        defer { isUpdatingRate = false }

        do {
            let kztPerRub = try await ExchangeRateService.fetchCurrentKztPerUnit(for: "RUB")
            settings.kztPerRub = kztPerRub

            let allTracked = trackedRates + extraRates
            let codes = Array(Set(allTracked.map { $0.code.uppercased() }))

            if !codes.isEmpty {
                let fetched = try await ExchangeRateService.fetchCurrentRates(for: codes)

                for rate in allTracked {
                    if let value = fetched[rate.code.uppercased()] {
                        rate.rubPerUnit = value
                    }
                }
            }

            try? modelContext.save()
            lastRatesRefreshAt = Date().timeIntervalSince1970
            rateMessage = "Курсы успешно обновлены"
        } catch {
            rateErrorMessage = error.localizedDescription
        }
    }

    private func deleteTrackedRates(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(displayedTrackedRates[index])
        }

        try? modelContext.save()
    }

    private func stringFromDouble(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
