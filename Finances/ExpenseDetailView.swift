import SwiftUI
import SwiftData

struct ExpenseDetailView: View {
    @Bindable var expense: Expense

    @Query
    private var settingsList: [AppSettings]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query(sort: \ExchangeRateEntry.date, order: .reverse)
    private var rates: [ExchangeRateEntry]

    private var settings: AppSettings? {
        settingsList.first
    }

    @State private var isEditing = false

    @State private var editedDate: Date = .now
    @State private var editedAmountText: String = ""
    @State private var editedOperationType: String = ""
    @State private var editedDetails: String = ""
    @State private var editedForeignAmountText: String = ""
    @State private var editedForeignCurrency: String = ""
    @State private var selectedCategoryName: String?
    @State private var noteText: String = ""

    private let operationTypes = ["Покупка", "Пополнение", "Перевод", "Снятие", "Разное"]

    var body: some View {
        Form {
            if expense.sourceFileName != nil {
                Section {
                    Label("Операция импортирована из PDF", systemImage: "doc.text")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Основная информация") {
                if isEditing {
                    DatePicker("Дата", selection: $editedDate, displayedComponents: .date)

                    TextField("Сумма", text: $editedAmountText)
                        .keyboardType(.decimalPad)

                    Picker("Тип операции", selection: $editedOperationType) {
                        ForEach(operationTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }

                    TextField("Детали", text: $editedDetails, axis: .vertical)
                        .lineLimit(2...5)
                } else {
                    detailRow(title: "Дата", value: formattedDate(expense.date))
                    detailRow(title: "Сумма", value: formattedAmount(expense.amount, currency: expense.accountCurrency))

                    if let rubAmount = expense.rubAmount {
                        detailRow(
                            title: "Сумма в рублях",
                            value: formattedRubAmount(rubAmount)
                        )
                    } else if let settings {
                        detailRow(
                            title: "Сумма в рублях",
                            value: formattedRubAmount(
                                CurrencyConverter.kztToRub(expense.amount, kztPerRub: settings.kztPerRub)
                            )
                        )
                    }

                    detailRow(title: "Тип операции", value: expense.operationType)
                    detailRow(title: "Детали", value: expense.details)
                }
            }

            Section("Иностранная валюта") {
                if isEditing {
                    TextField("Сумма", text: $editedForeignAmountText)
                        .keyboardType(.decimalPad)

                    TextField("Валюта", text: $editedForeignCurrency)
                } else if let foreignAmount = expense.foreignAmount,
                          let foreignCurrency = expense.foreignCurrency {
                    detailRow(
                        title: "Сумма",
                        value: formattedAmount(foreignAmount, currency: foreignCurrency)
                    )
                } else {
                    Text("Нет данных")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Категория") {
                Picker("Категория", selection: $selectedCategoryName) {
                    Text("Без категории").tag(nil as String?)

                    ForEach(categories) { category in
                        Text(category.name).tag(category.name as String?)
                    }
                }
                .pickerStyle(.navigationLink)
                .onChange(of: selectedCategoryName) { _, newValue in
                    expense.categoryName = newValue
                }
            }

            Section("Заметка") {
                TextField("Добавь заметку", text: $noteText, axis: .vertical)
                    .lineLimit(3...8)
                    .onChange(of: noteText) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        expense.note = trimmed.isEmpty ? nil : trimmed
                    }
            }

            Section("Техническая информация") {
                if let sourceFileName = expense.sourceFileName {
                    detailRow(title: "Источник", value: sourceFileName)
                }

                if let importedAt = expense.importedAt {
                    detailRow(title: "Импортировано", value: formattedDateTime(importedAt))
                }

                detailRow(title: "Создано", value: formattedDateTime(expense.createdAt))
            }
        }
        .navigationTitle("Операция")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button("Сохранить") {
                        saveChanges()
                    }
                } else {
                    Button("Редактировать") {
                        startEditing()
                    }
                }
            }
        }
        .onAppear {
            selectedCategoryName = expense.categoryName
            noteText = expense.note ?? ""
        }
    }

    private func startEditing() {
        editedDate = expense.date
        editedAmountText = stringFromDouble(abs(expense.amount))
        editedOperationType = expense.operationType
        editedDetails = expense.details
        editedForeignAmountText = expense.foreignAmount.map { stringFromDouble(abs($0)) } ?? ""
        editedForeignCurrency = expense.foreignCurrency ?? ""
        isEditing = true
    }

    private func saveChanges() {
        guard let parsedAmount = parseNumber(editedAmountText) else { return }

        let signedAmount: Double
        if editedOperationType == "Пополнение" {
            signedAmount = abs(parsedAmount)
        } else {
            signedAmount = -abs(parsedAmount)
        }

        expense.date = editedDate
        expense.amount = signedAmount
        expense.operationType = editedOperationType
        expense.details = editedDetails.trimmingCharacters(in: .whitespacesAndNewlines)

        if let parsedForeign = parseNumber(editedForeignAmountText),
           !editedForeignCurrency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if editedOperationType == "Пополнение" {
                expense.foreignAmount = abs(parsedForeign)
            } else {
                expense.foreignAmount = -abs(parsedForeign)
            }
            expense.foreignCurrency = editedForeignCurrency.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            expense.foreignAmount = nil
            expense.foreignCurrency = nil
        }

        expense.rubAmount = HistoricalCurrencyConverter.rubAmount(
            for: expense.amount,
            on: expense.date,
            rates: rates,
            fallbackKztPerRub: settings?.kztPerRub
        )

        isEditing = false
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

    private func parseNumber(_ string: String) -> Double? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")

        return Double(normalized)
    }

    private func stringFromDouble(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
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
