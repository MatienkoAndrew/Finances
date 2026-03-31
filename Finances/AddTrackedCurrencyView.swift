import SwiftUI
import SwiftData

struct AddTrackedCurrencyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @State private var selectedCode: String = "THB"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingCurrencyPicker = false

    private var selectedCurrency: SupportedCurrency {
        SupportedCurrency.byCode(selectedCode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Валюта") {
                    Button {
                        isShowingCurrencyPicker = true
                    } label: {
                        HStack {
                            Text("Выбрать валюту")
                                .foregroundStyle(.primary)

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(selectedCurrency.title)
                                    .foregroundStyle(.primary)

                                Text(selectedCurrency.symbol)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Button {
                        Task {
                            await saveCurrency()
                        }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                            }
                            Text(isLoading ? "Добавляем..." : "Добавить валюту")
                        }
                    }
                    .disabled(isLoading)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Новая валюта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingCurrencyPicker) {
                CurrencyPickerView(selectedCode: selectedCode) { newCode in
                    selectedCode = CurrencyDisplay.normalizedCode(from: newCode)
                }
            }
        }
    }

    @MainActor
    private func saveCurrency() async {
        let code = CurrencyDisplay.normalizedCode(from: selectedCode)

        let alreadyExists = trackedRates.contains {
            $0.code.uppercased() == code
        }

        if alreadyExists {
            errorMessage = "Эта валюта уже добавлена."
            return
        }

        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let rate = try await ExchangeRateService.fetchCurrentRates(for: [code])[code]

            guard let rate else {
                errorMessage = "Не удалось получить курс для \(code)."
                return
            }

            let newRate = TrackedExchangeRate(
                code: code,
                displayName: selectedCurrency.name,
                flag: defaultFlag(for: code),
                rubPerUnit: rate
            )

            modelContext.insert(newRate)
            try? modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func defaultFlag(for code: String) -> String {
        switch code {
        case "USD": return "🇺🇸"
        case "EUR": return "🇪🇺"
        case "CNY": return "🇨🇳"
        case "VND": return "🇻🇳"
        case "SGD": return "🇸🇬"
        case "THB": return "🇹🇭"
        case "LKR": return "🇱🇰"
        case "JPY": return "🇯🇵"
        case "KZT": return "🇰🇿"
        case "RUB": return "🇷🇺"
        default: return "🏳️"
        }
    }
}
