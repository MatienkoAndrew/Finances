//
//  ExpenseDetailView.swift
//  Finances
//
//  Created by Андрей Матиенко on 19.03.2026.
//


import SwiftUI
import SwiftData

struct ExpenseDetailView: View {
    @Bindable var expense: Expense

    @State private var selectedCategory: ExpenseCategory?
    @State private var noteText: String = ""

    var body: some View {
        Form {
            Section("Основная информация") {
                detailRow(title: "Дата", value: formattedDate(expense.date))
                detailRow(title: "Сумма", value: formattedAmount(expense.amount, currency: expense.accountCurrency))
                detailRow(title: "Тип операции", value: expense.operationType)
                detailRow(title: "Детали", value: expense.details)
            }

            if let foreignAmount = expense.foreignAmount,
               let foreignCurrency = expense.foreignCurrency {
                Section("Иностранная валюта") {
                    detailRow(
                        title: "Сумма",
                        value: formattedAmount(foreignAmount, currency: foreignCurrency)
                    )
                }
            }

            Section("Категория") {
                Picker("Категория", selection: $selectedCategory) {
                    Text("Без категории").tag(nil as ExpenseCategory?)

                    ForEach(ExpenseCategory.allCases, id: \.self) { category in
                        Text(category.title).tag(category as ExpenseCategory?)
                    }
                }
                .pickerStyle(.navigationLink)
                .onChange(of: selectedCategory) { _, newValue in
                    expense.category = newValue
                }
            }

            Section("Заметка") {
                TextField("Добавь заметку", text: $noteText, axis: .vertical)
                    .lineLimit(3...8)
                    .onAppear {
                        noteText = expense.note ?? ""
                    }
                    .onChange(of: noteText) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        expense.note = trimmed.isEmpty ? nil : trimmed
                    }
            }

            Section("Техническая информация") {
                if let sourceFileName = expense.sourceFileName {
                    detailRow(title: "Источник", value: sourceFileName)
                }

                if let fingerprint = expense.fingerprint {
                    detailRow(title: "Fingerprint", value: fingerprint)
                }

                if let importedAt = expense.importedAt {
                    detailRow(title: "Импортировано", value: formattedDateTime(importedAt))
                }

                detailRow(title: "Создано", value: formattedDateTime(expense.createdAt))
            }
        }
        .navigationTitle("Операция")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedCategory = expense.category
            noteText = expense.note ?? ""
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
}