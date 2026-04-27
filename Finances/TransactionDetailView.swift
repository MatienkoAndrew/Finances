import SwiftUI
import SwiftUI
import SwiftData

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var transaction: Transaction

    @Query(sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @Query
    private var settingsList: [AppSettings]

    @State private var isEditing = false

    @State private var editedDate: Date = .now
    @State private var editedAmountText: String = ""
    @State private var editedCurrencyCode: String = "VND"
    @State private var editedToAmountText: String = ""
    @State private var editedToCurrencyCode: String = "VND"
    @State private var editedDetails: String = ""
    @State private var editedCategoryName: String?
    @State private var editedNote: String = ""
    @State private var editedFromAccount: Account?
    @State private var editedToAccount: Account?

    @State private var isShowingCurrencyPicker = false
    @State private var isShowingToCurrencyPicker = false

    private var settings: AppSettings? {
        settingsList.first
    }

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    var body: some View {
        Form {
            Section("Основная информация") {
                if isEditing {
                    DatePicker("Дата", selection: $editedDate, displayedComponents: .date)

                    TextField("Сумма", text: $editedAmountText)
                        .keyboardType(.decimalPad)

                    Button {
                        isShowingCurrencyPicker = true
                    } label: {
                        HStack {
                            Text("Валюта")
                                .foregroundStyle(.primary)

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(CurrencyDisplay.title(for: editedCurrencyCode))
                                    .foregroundStyle(.primary)

                                Text(CurrencyDisplay.symbol(for: editedCurrencyCode))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if transaction.kind == .transfer {
                        TextField("Сумма зачисления", text: $editedToAmountText)
                            .keyboardType(.decimalPad)

                        Button {
                            isShowingToCurrencyPicker = true
                        } label: {
                            HStack {
                                Text("Валюта зачисления")
                                    .foregroundStyle(.primary)

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(CurrencyDisplay.title(for: editedToCurrencyCode))
                                        .foregroundStyle(.primary)

                                    Text(CurrencyDisplay.symbol(for: editedToCurrencyCode))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("Детали", text: $editedDetails, axis: .vertical)
                        .lineLimit(2...4)

                    if let preview = liveRubPreview {
                        detailRow(title: "Будет сохранено в ₽", value: formattedAmount(preview, currency: "₽"))
                    }
                } else {
                    detailRow(title: "Тип", value: transaction.kind.title)
                    detailRow(title: "Дата", value: formattedDate(transaction.date))
                    detailRow(
                        title: "Сумма",
                        value: formattedAmount(
                            transaction.amount,
                            currency: CurrencyDisplay.symbol(for: transaction.currencyCode)
                        )
                    )

                    if transaction.kind == .transfer {
                        detailRow(
                            title: "Зачислено",
                            value: formattedAmount(
                                transaction.creditedAmount,
                                currency: CurrencyDisplay.symbol(for: transaction.creditedCurrencyCode)
                            )
                        )
                    }

                    if let rubAmount = TransactionRubConverter.displayRubAmount(
                        for: transaction,
                        settings: settings,
                        trackedRates: trackedRates
                    ) {
                        detailRow(title: "Сумма в рублях", value: formattedAmount(rubAmount, currency: "₽"))
                    }

                    detailRow(title: "Валюта", value: CurrencyDisplay.title(for: transaction.currencyCode))
                    detailRow(title: "Детали", value: transaction.details)
                }
            }

            Section("Счета") {
                if isEditing {
                    if transaction.kind == .expense || transaction.kind == .transfer {
                        Picker("Откуда", selection: $editedFromAccount) {
                            Text("Не выбрано").tag(nil as Account?)

                            ForEach(activeAccounts) { account in
                                Text(account.displayTitle).tag(Optional(account))
                            }
                        }
                    }

                    if transaction.kind == .income || transaction.kind == .transfer {
                        Picker("Куда", selection: $editedToAccount) {
                            Text("Не выбрано").tag(nil as Account?)

                            ForEach(activeAccounts) { account in
                                Text(account.displayTitle).tag(Optional(account))
                            }
                        }
                    }
                } else {
                    detailRow(title: "Откуда", value: transaction.fromAccount?.displayTitle ?? "—")
                    detailRow(title: "Куда", value: transaction.toAccount?.displayTitle ?? "—")
                }
            }

            if transaction.kind == .expense {
                Section("Категория") {
                    Picker("Категория", selection: $editedCategoryName) {
                        ForEach(categories) { category in
                            Text(category.name).tag(category.name as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: editedCategoryName) { _, newValue in
                        transaction.categoryName = newValue
                        try? modelContext.save()
                    }
                }
            }

            Section("Заметка") {
                if isEditing {
                    TextField("Заметка", text: $editedNote, axis: .vertical)
                        .lineLimit(2...6)
                } else {
                    detailRow(title: "Заметка", value: transaction.note ?? "—")
                }
            }
            
            tagsSection

            Section("Техническая информация") {
                detailRow(title: "Источник", value: transaction.sourceFileName ?? "—")

                if let importedAt = transaction.importedAt {
                    detailRow(title: "Импортировано", value: formattedDateTime(importedAt))
                }

                detailRow(title: "Создано", value: formattedDateTime(transaction.createdAt))
            }

            Section {
                Button(role: .destructive) {
                    deleteTransaction()
                } label: {
                    Text("Удалить транзакцию")
                }
            }
        }
        .navigationTitle("Транзакция")
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
        .sheet(isPresented: $isShowingCurrencyPicker) {
            CurrencyPickerView(selectedCode: editedCurrencyCode) { newCode in
                editedCurrencyCode = CurrencyDisplay.normalizedCode(from: newCode)
            }
        }
        .sheet(isPresented: $isShowingToCurrencyPicker) {
            CurrencyPickerView(selectedCode: editedToCurrencyCode) { newCode in
                editedToCurrencyCode = CurrencyDisplay.normalizedCode(from: newCode)
            }
        }
        .onAppear {
            syncEditedStateFromTransaction()
        }
    }

    private var liveRubPreview: Double? {
        guard let amount = parseNumber(editedAmountText) else { return nil }

        return TransactionRubConverter.rubAmount(
            amount: amount,
            currencyCode: editedCurrencyCode,
            settings: settings,
            trackedRates: trackedRates
        )
    }

    private func startEditing() {
        syncEditedStateFromTransaction()
        isEditing = true
    }

    private func syncEditedStateFromTransaction() {
        editedDate = transaction.date
        editedAmountText = stringFromDouble(transaction.amount)
        editedCurrencyCode = CurrencyDisplay.normalizedCode(from: transaction.currencyCode)
        editedToAmountText = stringFromDouble(transaction.creditedAmount)
        editedToCurrencyCode = CurrencyDisplay.normalizedCode(from: transaction.creditedCurrencyCode)
        editedDetails = transaction.details
        editedCategoryName = transaction.categoryName
        editedNote = transaction.note ?? ""
        editedFromAccount = transaction.fromAccount
        editedToAccount = transaction.toAccount
    }

    private func saveChanges() {
        guard let parsedAmount = parseNumber(editedAmountText) else { return }

        transaction.date = editedDate
        transaction.amount = parsedAmount
        transaction.currencyCode = CurrencyDisplay.normalizedCode(from: editedCurrencyCode)
        transaction.details = editedDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.categoryName = editedCategoryName

        let trimmedNote = editedNote.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.note = trimmedNote.isEmpty ? nil : trimmedNote

        switch transaction.kind {
        case .expense:
            transaction.fromAccount = editedFromAccount
            transaction.toAccount = nil
            transaction.toAmount = nil
            transaction.toCurrencyCode = nil

        case .income:
            transaction.fromAccount = nil
            transaction.toAccount = editedToAccount
            transaction.toAmount = nil
            transaction.toCurrencyCode = nil

        case .transfer:
            transaction.fromAccount = editedFromAccount
            transaction.toAccount = editedToAccount

            if let parsedToAmount = parseNumber(editedToAmountText) {
                transaction.toAmount = parsedToAmount
                transaction.toCurrencyCode = CurrencyDisplay.normalizedCode(from: editedToCurrencyCode)
            } else {
                transaction.toAmount = nil
                transaction.toCurrencyCode = nil
            }
        }

        transaction.rubAmount = TransactionRubConverter.rubAmount(
            amount: transaction.amount,
            currencyCode: transaction.currencyCode,
            settings: settings,
            trackedRates: trackedRates
        )

        try? modelContext.save()
        isEditing = false
    }

    private func deleteTransaction() {
        modelContext.delete(transaction)
        try? modelContext.save()
        dismiss()
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
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

    private func formattedAmount(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        let number = formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        return "\(number) \(currency)"
    }
    
    // MARK: - Tags Section
    
    @Query(sort: \TransactionTag.createdAt, order: .reverse)
    private var allTags: [TransactionTag]
    
    @State private var showingTagPicker = false
    
    private var tagsSection: some View {
        Section("Метки") {
            if let tags = transaction.tagNames, !tags.isEmpty {
                ForEach(tags, id: \.self) { tagName in
                    HStack {
                        if let tag = allTags.first(where: { $0.name == tagName }) {
                            Text(tag.displayIcon)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tagName)
                                    .font(.body)
                                
                                if tag.startDate != nil || tag.endDate != nil {
                                    Text(tag.periodDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text("🏷️")
                                .font(.title3)
                            Text(tagName)
                        }
                        
                        Spacer()
                        
                        Button(role: .destructive) {
                            withAnimation {
                                transaction.removeTag(tagName)
                                try? modelContext.save()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Button {
                showingTagPicker = true
            } label: {
                Label("Добавить метку", systemImage: "tag.fill")
            }
        }
        .sheet(isPresented: $showingTagPicker) {
            TagPickerView(transaction: transaction)
        }
    }
}

// MARK: - Tag Picker View

struct TagPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \TransactionTag.createdAt, order: .reverse)
    private var allTags: [TransactionTag]
    
    let transaction: Transaction
    
    var body: some View {
        NavigationStack {
            List {
                if availableTags.isEmpty {
                    ContentUnavailableView(
                        "Нет доступных меток",
                        systemImage: "tag.slash",
                        description: Text("Все метки уже добавлены к этой транзакции или метки ещё не созданы")
                    )
                } else {
                    ForEach(availableTags) { tag in
                        Button {
                            addTag(tag)
                        } label: {
                            HStack {
                                Text(tag.displayIcon)
                                    .font(.title3)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tag.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    
                                    if tag.startDate != nil || tag.endDate != nil {
                                        Text(tag.periodDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                // Показываем галочку, если дата транзакции попадает в период метки
                                if tag.contains(date: transaction.date) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Выбрать метку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var availableTags: [TransactionTag] {
        allTags.filter { tag in
            !(transaction.tagNames?.contains(tag.name) ?? false)
        }
    }
    
    private func addTag(_ tag: TransactionTag) {
        transaction.addTag(tag.name)
        try? modelContext.save()
        dismiss()
    }
}
