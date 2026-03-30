import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query
    private var expenses: [Expense]

    @Query
    private var settingsList: [AppSettings]

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @State private var kztPerRubText: String = ""

    @State private var isUpdatingRate = false
    @State private var rateMessage: String?
    @State private var rateErrorMessage: String?

    @State private var isShowingAddCurrency = false

    private var settings: AppSettings {
        if let existing = settingsList.first {
            return existing
        } else {
            let newSettings = AppSettings()
            modelContext.insert(newSettings)
            return newSettings
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Курс для аналитики") {
                    TextField("Сколько KZT в 1 RUB", text: $kztPerRubText)
                        .keyboardType(.decimalPad)
                        .onAppear {
                            kztPerRubText = stringFromDouble(settings.kztPerRub)
                        }
                        .onChange(of: kztPerRubText) { _, newValue in
                            if let parsed = parseNumber(newValue), parsed > 0 {
                                settings.kztPerRub = parsed
                            }
                        }

                    Button {
                        Task {
                            await updateRubRateFromAPI()
                        }
                    } label: {
                        HStack {
                            if isUpdatingRate {
                                ProgressView()
                            }
                            Text(isUpdatingRate ? "Обновляем..." : "Обновить курс RUB из API")
                        }
                    }
                    .disabled(isUpdatingRate)

                    Text("Этот курс используется для пересчёта всех сумм в рубли.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Текущий курс") {
                    Text("1 RUB = \(stringFromDouble(settings.kztPerRub)) KZT")
                    Text("1 KZT = \(rubPerKztString()) RUB")
                        .foregroundStyle(.secondary)
                }

                Section("Рубли") {
                    Button("Пересчитать суммы в рублях") {
                        ExpenseRubRecalculator.recalculate(
                            expenses: expenses,
                            rates: [],
                            fallbackKztPerRub: settings.kztPerRub
                        )
                    }

                    Text("Используется текущий курс RUB из настроек.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Дополнительные курсы") {
                    if trackedRates.isEmpty {
                        Text("Нет дополнительных валют")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(trackedRates) { rate in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(rate.flag) \(rate.code) — \(rate.displayName)")
                                        .font(.headline)

                                    Text("1 \(rate.code) = \(stringFromDouble(rate.rubPerUnit)) RUB")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                        }
                        .onDelete(perform: deleteTrackedRates)
                    }

                    Button("Добавить валюту") {
                        isShowingAddCurrency = true
                    }

                    if !trackedRates.isEmpty {
                        Button("Обновить дополнительные курсы из API") {
                            Task {
                                await updateTrackedRatesFromAPI()
                            }
                        }
                        .disabled(isUpdatingRate)
                    }

                    Text("При добавлении курс подтягивается сразу из API. Эти курсы хранятся для информации и не участвуют в аналитике.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            .alert("Курс обновлён", isPresented: Binding(
                get: { rateMessage != nil },
                set: { if !$0 { rateMessage = nil } }
            )) {
                Button("OK", role: .cancel) { rateMessage = nil }
            } message: {
                Text(rateMessage ?? "")
            }
            .alert("Ошибка обновления курса", isPresented: Binding(
                get: { rateErrorMessage != nil },
                set: { if !$0 { rateErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { rateErrorMessage = nil }
            } message: {
                Text(rateErrorMessage ?? "")
            }
        }
    }

    private func parseNumber(_ string: String) -> Double? {
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")

        return Double(normalized)
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

    private func rubPerKztString() -> String {
        guard settings.kztPerRub > 0 else { return "0" }
        return stringFromDouble(1 / settings.kztPerRub)
    }

    @MainActor
    private func updateRubRateFromAPI() async {
        isUpdatingRate = true
        defer { isUpdatingRate = false }

        do {
            let rate = try await ExchangeRateService.fetchCurrentKztPerUnit(for: "RUB")
            settings.kztPerRub = rate
            kztPerRubText = stringFromDouble(rate)

            ExpenseRubRecalculator.recalculate(
                expenses: expenses,
                rates: [],
                fallbackKztPerRub: settings.kztPerRub
            )

            rateMessage = "Текущий курс RUB обновлён"
        } catch {
            rateErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func updateTrackedRatesFromAPI() async {
        isUpdatingRate = true
        defer { isUpdatingRate = false }

        do {
            let codes = trackedRates.map(\.code)
            let fetched = try await ExchangeRateService.fetchCurrentRates(for: codes)

            for rate in trackedRates {
                if let value = fetched[rate.code.uppercased()] {
                    rate.rubPerUnit = value
                }
            }

            rateMessage = "Дополнительные курсы обновлены"
        } catch {
            rateErrorMessage = error.localizedDescription
        }
    }

    private func deleteTrackedRates(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(trackedRates[index])
        }
    }
}
