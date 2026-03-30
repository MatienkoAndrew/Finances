import SwiftUI
import SwiftData

struct AddTrackedCurrencyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @State private var selectedCurrency: SupportedTrackedCurrency?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var selectableCurrencies: [SupportedTrackedCurrency] {
        SupportedTrackedCurrencies.all.filter { currency in
            !trackedRates.contains { $0.code.uppercased() == currency.code.uppercased() }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Валюта") {
                    if selectableCurrencies.isEmpty {
                        Text("Все доступные валюты уже добавлены")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(
                            "Валюта",
                            selection: Binding(
                                get: { selectedCurrency ?? selectableCurrencies.first },
                                set: { selectedCurrency = $0 }
                            )
                        ) {
                            ForEach(selectableCurrencies) { currency in
                                Text("\(currency.flag) \(currency.code) — \(currency.displayName)")
                                    .tag(Optional(currency))
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                if let selectedCurrency {
                    Section("Предпросмотр") {
                        Text("\(selectedCurrency.flag) \(selectedCurrency.code) — \(selectedCurrency.displayName)")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Добавить валюту")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await save()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Сохранить")
                        }
                    }
                    .disabled(selectableCurrencies.isEmpty || isSaving || selectedCurrency == nil)
                }
            }
            .onAppear {
                if selectedCurrency == nil {
                    selectedCurrency = selectableCurrencies.first
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard let selectedCurrency else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let rate = try await ExchangeRateService.fetchCurrentRubPerUnit(for: selectedCurrency.code)

            let item = TrackedExchangeRate(
                code: selectedCurrency.code,
                displayName: selectedCurrency.displayName,
                flag: selectedCurrency.flag,
                rubPerUnit: rate
            )

            modelContext.insert(item)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
