//
//  SettingsView.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import SwiftUI
import SwiftData


struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query
    private var settingsList: [AppSettings]

    @State private var kztPerRubText: String = ""
    

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
                Section("Курс валют") {
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

                    Text("Например, если 1 RUB = 5,8 KZT, введи 5,8")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Текущий курс") {
                    Text("1 RUB = \(stringFromDouble(settings.kztPerRub)) KZT")
                    Text("1 KZT = \(rubPerKztString()) RUB")
                        .foregroundStyle(.secondary)
                }
                
                Section("Данные") {
                    NavigationLink("Управление категориями") {
                        CategoriesView()
                    }
                }
            }
            .navigationTitle("Настройки")
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
}
