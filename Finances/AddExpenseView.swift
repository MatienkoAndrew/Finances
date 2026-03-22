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
    
    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @State private var date: Date = .now
    @State private var amountText: String = ""
    @State private var accountCurrency: String = "₸"
    @State private var operationType: String = "Покупка"
    @State private var details: String = ""

    @State private var foreignAmountText: String = ""
    @State private var foreignCurrency: String = ""

    @State private var selectedCategoryName: String? = nil
    @State private var note: String = ""

    @FocusState private var focusedField: Field?

    enum Field {
        case amount
        case details
        case foreignAmount
        case foreignCurrency
        case note
    }

    private let operationTypes: [String] = [
        "Покупка",
        "Пополнение",
        "Перевод",
        "Снятие",
        "Разное"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Основное") {
                    DatePicker("Дата", selection: $date, displayedComponents: .date)

                    TextField("Сумма, например 1761.07", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .amount)

                    TextField("Валюта счета", text: $accountCurrency)
                        .textInputAutocapitalization(.never)

                    Picker("Тип операции", selection: $operationType) {
                        ForEach(operationTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }

                    TextField("Детали", text: $details, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .details)
                }

                Section("Иностранная валюта") {
                    TextField("Сумма в другой валюте", text: $foreignAmountText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .foreignAmount)

                    TextField("Код валюты, например USD / VND", text: $foreignCurrency)
                        .textInputAutocapitalization(.characters)
                        .focused($focusedField, equals: .foreignCurrency)
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

    private var canSave: Bool {
        parsedAmount != nil && !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var parsedAmount: Double? {
        guard let value = parseNumber(from: amountText) else { return nil }
        return abs(value)
    }

    private var parsedForeignAmount: Double? {
        guard !foreignAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let value = parseNumber(from: foreignAmountText) else { return nil }
        return abs(value)
    }

    private func parseNumber(from string: String) -> Double? {
        let normalized = string
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func saveExpense() {
        guard let parsedAmount = parsedAmount else { return }

        let trimmedCurrency = accountCurrency.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedForeignCurrency = foreignCurrency.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        let signedAmount: Double
        if operationType == "Пополнение" {
            signedAmount = abs(parsedAmount)
        } else {
            signedAmount = -abs(parsedAmount)
        }

        let signedForeignAmount: Double?
        if let parsedForeignAmount {
            if operationType == "Пополнение" {
                signedForeignAmount = abs(parsedForeignAmount)
            } else {
                signedForeignAmount = -abs(parsedForeignAmount)
            }
        } else {
            signedForeignAmount = nil
        }

        let expense = Expense(
            date: date,
            amount: signedAmount,
            accountCurrency: trimmedCurrency.isEmpty ? "₸" : trimmedCurrency,
            operationType: operationType,
            details: trimmedDetails,
            foreignAmount: signedForeignAmount,
            foreignCurrency: trimmedForeignCurrency.isEmpty ? nil : trimmedForeignCurrency,
            categoryName: selectedCategoryName,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )

        modelContext.insert(expense)
        dismiss()
    }
}
