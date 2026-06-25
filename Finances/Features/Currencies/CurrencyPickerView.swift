//
//  CurrencyPickerView.swift
//  Finances
//
//  Created by Андрей Матиенко on 31.03.2026.
//


import SwiftUI

struct CurrencyPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let selectedCode: String
    let onSelect: (String) -> Void

    @State private var searchText = ""

    private var filteredCurrencies: [SupportedCurrency] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SupportedCurrency.all }

        let query = trimmed.lowercased()

        return SupportedCurrency.all.filter { currency in
            currency.code.lowercased().contains(query) ||
            currency.name.lowercased().contains(query) ||
            currency.symbol.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredCurrencies) { currency in
                    Button {
                        onSelect(currency.code)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(currency.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)

                                Text(currency.symbol)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if currency.code == CurrencyDisplay.normalizedCode(from: selectedCode) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Выбор валюты")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Код, название или символ")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }
}