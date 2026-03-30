//
//  AddExpenseView.swift
//  Finances
//
//  Created by Андрей Матиенко on 19.03.2026.
//

import SwiftUI
import SwiftData

struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query
    private var settingsList: [AppSettings]

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @State private var date: Date = .now
    @State private var amountText: String = ""
    @State private var selectedCurrencyCode: String = "KZT"
    @State private var operationType: String = "Покупка"
    @State private var details: String = ""
    @State private var selectedCategoryName: String? = nil
    @State private var note: String = ""

    @FocusState private var focusedField: Field?

    enum Field {
        case amount
        case details
        case note
    }

    private let operationTypes: [String] = [
        "Покупка",
        "Пополнение",
        "Перевод",
        "Снятие",
        "Разное"
    ]

    private var settings: AppSettings? {
        settingsList.first
    }

    private var parsedEnteredAmount: Double? {
        guard let value = parseNumber(from: amountText) else { return nil }
        return abs(value)
    }

    private var convertedKztAmount: Double? {
        guard let parsedEnteredAmount,
              let settings
        else { return nil }

        return ManualExpenseCurrencyConverter.kztAmount(
            enteredAmount: parsedEnteredAmount,
            currencyCode: selectedCurrencyCode,
            kztPerRub: settings.kztPerRub,
            trackedRates: trackedRates
        )
    }

    private var convertedRubAmount: Double? {
        guard let parsedEnteredAmount,
              let settings
        else { return nil }

        return ManualExpenseCurrencyConverter.rubAmount(
            enteredAmount: parsedEnteredAmount,
            currencyCode: selectedCurrencyCode,
            kztPerRub: settings.kztPerRub,
            trackedRates: trackedRates
        )
    }

    private var needsTrackedRateWarning: Bool {
        selectedCurrencyCode != "KZT"
        && selectedCurrencyCode != "RUB"
        && convertedKztAmount == nil
    }

    private var canSave: Bool {
        parsedEnteredAmount != nil
        && convertedKztAmount != nil
        && !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Основное") {
                    DatePicker("Дата", selection: $date, displayedComponents: .date)

                    TextField("Сумма, например 10000", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .amount)

                    Picker("Валюта", selection: $selectedCurrencyCode) {
                        ForEach(SupportedInputCurrencies.all) { currency in
                            Text("\(currency.flag) \(currency.code) — \(currency.displayName)")
                                .tag(currency.code)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    if let convertedKztAmount {
                        Text("Будет сохранено: \(formattedAmount(convertedKztAmount, currency: "₸"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let convertedRubAmount {
                        Text("Примерно: \(formattedRubAmount(convertedRubAmount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if needsTrackedRateWarning {
                        Text("Для валюты \(selectedCurrencyCode) нет курса. Добавь её в Настройках → Дополнительные курсы.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Picker("Тип операции", selection: $operationType) {
                        ForEach(operationTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }

                    Text(operationType == "Пополнение"
                         ? "Сумма будет сохранена как пополнение (+)"
                         : "Сумма будет сохранена как расход (-)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Детали", text: $details, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .details)
                }

                Section("Категория") {
                    Picker("Категория", selection: $selectedCategoryName) {
                        Text("Без категории").tag(nil as String?)

                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.name))
                        }
                    }
                }

                Section("Заметка") {
                    TextField("Комментарий", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .note)
                }
            }
            .navigationTitle("Новая операция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        saveExpense()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func parseNumber(from string: String) -> Double? {
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func saveExpense() {
        guard let parsedEnteredAmount,
              let settings,
              let convertedKztAmount
        else { return }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        let signedAmount: Double
        if operationType == "Пополнение" {
            signedAmount = abs(convertedKztAmount)
        } else {
            signedAmount = -abs(convertedKztAmount)
        }

        let baseRubAmount = ManualExpenseCurrencyConverter.rubAmount(
            enteredAmount: parsedEnteredAmount,
            currencyCode: selectedCurrencyCode,
            kztPerRub: settings.kztPerRub,
            trackedRates: trackedRates
        )

        let signedRubAmount: Double?
        if let baseRubAmount {
            if operationType == "Пополнение" {
                signedRubAmount = abs(baseRubAmount)
            } else {
                signedRubAmount = -abs(baseRubAmount)
            }
        } else {
            signedRubAmount = nil
        }

        let signedForeignAmount: Double?
        if selectedCurrencyCode == "KZT" {
            signedForeignAmount = nil
        } else if operationType == "Пополнение" {
            signedForeignAmount = abs(parsedEnteredAmount)
        } else {
            signedForeignAmount = -abs(parsedEnteredAmount)
        }

        let expense = Expense(
            date: date,
            amount: signedAmount,
            accountCurrency: "₸",
            operationType: operationType,
            details: trimmedDetails,
            foreignAmount: signedForeignAmount,
            foreignCurrency: selectedCurrencyCode == "KZT" ? nil : selectedCurrencyCode,
            rubAmount: signedRubAmount,
            categoryName: selectedCategoryName,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )

        modelContext.insert(expense)
        dismiss()
    }

    private func formattedAmount(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        let sign = amount < 0 ? "-" : "+"
        let number = formatter.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"

        return "\(sign) \(number) \(currency)"
    }

    private func formattedRubAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        let sign = amount < 0 ? "-" : "+"
        let number = formatter.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"

        return "\(sign) \(number) ₽"
    }
}
