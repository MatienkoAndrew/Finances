import SwiftUI
import SwiftData

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @Query
    private var settingsList: [AppSettings]

    private var settings: AppSettings? {
        settingsList.first
    }

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    @State private var date: Date = .now
    @State private var selectedKind: TransactionKind = .expense

    @State private var amountText: String = ""
    @State private var currencyCode: String = "VND"

    @State private var toAmountText: String = ""
    @State private var toCurrencyCode: String = "VND"

    @State private var details: String = ""
    @State private var selectedCategoryName: String?
    @State private var note: String = ""

    @State private var selectedFromAccount: Account?
    @State private var selectedToAccount: Account?

    @State private var isShowingCurrencyPicker = false
    @State private var isShowingToCurrencyPicker = false

    @State private var didApplyInitialDefaults = false
    @State private var isShowingAddCategory = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Основная информация") {
                    DatePicker("Дата", selection: $date, displayedComponents: .date)

                    Picker("Тип", selection: $selectedKind) {
                        ForEach(TransactionKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.systemImage)
                                .tag(kind)
                        }
                    }

                    TextField("Сумма", text: $amountText)
                        .keyboardType(.decimalPad)
                        .onChange(of: amountText) { _, newValue in
                            let formatted = formatAmountInput(newValue)
                            if formatted != newValue {
                                amountText = formatted
                            }
                        }

                    Button {
                        isShowingCurrencyPicker = true
                    } label: {
                        HStack {
                            Text("Валюта")
                                .foregroundStyle(.primary)

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(CurrencyDisplay.title(for: currencyCode))
                                    .foregroundStyle(.primary)

                                Text(CurrencyDisplay.symbol(for: currencyCode))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if let liveRubPreview {
                        Text("≈ \(formattedRubAmount(liveRubPreview))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if selectedKind == .expense {
                        Menu {
                            ForEach(categories) { category in
                                Button {
                                    selectedCategoryName = category.name
                                } label: {
                                    Text(category.name)
                                }
                            }

                            Divider()

                            Button {
                                isShowingAddCategory = true
                            } label: {
                                Label("Новая категория", systemImage: "plus.circle.fill")
                            }
                        } label: {
                            HStack {
                                Text("Категория")
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text(selectedCategoryName ?? "Другое")
                                    .foregroundStyle(.secondary)

                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    TextField(detailsPlaceholder, text: $details, axis: .vertical)
                        .lineLimit(2...4)
                }

                if selectedKind == .transfer {
                    Section("Зачисление") {
                        TextField("Сумма зачисления", text: $toAmountText)
                            .keyboardType(.decimalPad)
                            .onChange(of: toAmountText) { _, newValue in
                                let formatted = formatAmountInput(newValue)
                                if formatted != newValue {
                                    toAmountText = formatted
                                }
                            }

                        Button {
                            isShowingToCurrencyPicker = true
                        } label: {
                            HStack {
                                Text("Валюта зачисления")
                                    .foregroundStyle(.primary)

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(CurrencyDisplay.title(for: toCurrencyCode))
                                        .foregroundStyle(.primary)

                                    Text(CurrencyDisplay.symbol(for: toCurrencyCode))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Счета") {
                    if selectedKind == .expense || selectedKind == .transfer {
                        Picker("Откуда", selection: $selectedFromAccount) {
                            Text("Выбери счет").tag(nil as Account?)

                            ForEach(activeAccounts) { account in
                                Text(account.displayTitle).tag(Optional(account))
                            }
                        }
                    }

                    if selectedKind == .income || selectedKind == .transfer {
                        Picker("Куда", selection: $selectedToAccount) {
                            Text("Выбери счет").tag(nil as Account?)

                            ForEach(activeAccounts) { account in
                                Text(account.displayTitle).tag(Optional(account))
                            }
                        }
                    }
                }

                Section("Заметка") {
                    TextField("Добавь заметку", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle("Новая транзакция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        saveTransaction()
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isShowingCurrencyPicker) {
                CurrencyPickerView(selectedCode: currencyCode) { newCode in
                    currencyCode = CurrencyDisplay.normalizedCode(from: newCode)
                }
            }
            .sheet(isPresented: $isShowingToCurrencyPicker) {
                CurrencyPickerView(selectedCode: toCurrencyCode) { newCode in
                    toCurrencyCode = CurrencyDisplay.normalizedCode(from: newCode)
                }
            }
            .sheet(isPresented: $isShowingAddCategory) {
                AddCategorySheet { newCategoryName in
                    selectedCategoryName = newCategoryName
                }
            }
            .onAppear {
                applyInitialDefaultsIfNeeded()
            }
            .onChange(of: selectedKind) { _, _ in
                applyDefaultAccountsIfNeeded(force: true)
            }
            .onChange(of: currencyCode) { _, _ in
                applyDefaultAccountsIfNeeded(force: true)
            }
            .onChange(of: toCurrencyCode) { _, _ in
                applyDefaultAccountsIfNeeded(force: true)
            }
        }
    }

    private var canSave: Bool {
        guard parseNumber(amountText) != nil else { return false }
        guard !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        switch selectedKind {
        case .expense:
            return selectedFromAccount != nil

        case .income:
            return selectedToAccount != nil

        case .transfer:
            guard selectedFromAccount != nil, selectedToAccount != nil else { return false }
            guard parseNumber(toAmountText) != nil else { return false }
            return true
        }
    }
    
    private var detailsPlaceholder: String {
        switch selectedKind {
        case .expense:
            return "Описание"
        case .income:
            return "Откуда пришло?"
        case .transfer:
            return "Описание перевода"
        }
    }

    private var liveRubPreview: Double? {
        guard let parsedAmount = parseNumber(amountText) else { return nil }

        return TransactionRubConverter.rubAmount(
            amount: parsedAmount,
            currencyCode: currencyCode,
            settings: settings,
            trackedRates: trackedRates
        )
    }

    private func applyInitialDefaultsIfNeeded() {
        guard !didApplyInitialDefaults else { return }
        didApplyInitialDefaults = true

        currencyCode = "VND"
        toCurrencyCode = "VND"

        applyDefaultAccountsIfNeeded(force: true)
    }

    private func applyDefaultAccountsIfNeeded(force: Bool = false) {
        switch selectedKind {
        case .expense:
            if force || selectedFromAccount == nil || selectedFromAccount?.isArchived == true {
                selectedFromAccount = defaultAccount(for: currencyCode)
            }
            selectedToAccount = nil

        case .income:
            selectedFromAccount = nil
            if force || selectedToAccount == nil || selectedToAccount?.isArchived == true {
                selectedToAccount = defaultAccount(for: currencyCode)
            }

        case .transfer:
            if force || selectedFromAccount == nil || selectedFromAccount?.isArchived == true {
                selectedFromAccount = defaultAccount(for: currencyCode)
            }

            if force || selectedToAccount == nil || selectedToAccount?.isArchived == true {
                selectedToAccount = defaultAccount(for: toCurrencyCode)
            }
        }
    }

    private func defaultAccount(for currencyCode: String) -> Account? {
        let normalized = CurrencyDisplay.normalizedCode(from: currencyCode)

        return activeAccounts.first {
            CurrencyDisplay.normalizedCode(from: $0.currencyCode) == normalized &&
            $0.type == .cash
        }
        ?? activeAccounts.first {
            CurrencyDisplay.normalizedCode(from: $0.currencyCode) == normalized
        }
        ?? AccountLookup.kaspi(in: activeAccounts)
        ?? activeAccounts.first
    }

    private func saveTransaction() {
        guard let parsedAmount = parseNumber(amountText) else { return }

        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedCurrencyCode = CurrencyDisplay.normalizedCode(from: currencyCode)

        let rubAmount = TransactionRubConverter.rubAmount(
            amount: parsedAmount,
            currencyCode: normalizedCurrencyCode,
            settings: settings,
            trackedRates: trackedRates
        )

        let transaction: Transaction

        switch selectedKind {
        case .expense:
            transaction = Transaction(
                date: date,
                kindRaw: TransactionKind.expense.rawValue,
                amount: parsedAmount,
                currencyCode: normalizedCurrencyCode,
                details: trimmedDetails,
                rubAmount: rubAmount,
                categoryName: selectedCategoryName,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                fromAccount: selectedFromAccount,
                toAccount: nil
            )

        case .income:
            transaction = Transaction(
                date: date,
                kindRaw: TransactionKind.income.rawValue,
                amount: parsedAmount,
                currencyCode: normalizedCurrencyCode,
                details: trimmedDetails,
                rubAmount: rubAmount,
                categoryName: nil,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                fromAccount: nil,
                toAccount: selectedToAccount
            )

        case .transfer:
            guard let parsedToAmount = parseNumber(toAmountText) else { return }

            transaction = Transaction(
                date: date,
                kindRaw: TransactionKind.transfer.rawValue,
                amount: parsedAmount,
                currencyCode: normalizedCurrencyCode,
                toAmount: parsedToAmount,
                toCurrencyCode: CurrencyDisplay.normalizedCode(from: toCurrencyCode),
                details: trimmedDetails,
                rubAmount: rubAmount,
                categoryName: nil,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                fromAccount: selectedFromAccount,
                toAccount: selectedToAccount
            )
        }

        modelContext.insert(transaction)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save transaction: \(error)")
        }
    }

    private func parseNumber(_ string: String) -> Double? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")

        return Double(normalized)
    }

    private func formatAmountInput(_ input: String) -> String {
        let filtered = input.filter { $0.isNumber || $0 == "," || $0 == "." || $0 == " " }
        let normalized = filtered
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: ",")

        guard !normalized.isEmpty else { return "" }

        let parts = normalized.split(separator: ",", omittingEmptySubsequences: false)
        let integerDigits = String(parts.first ?? "").filter(\.isNumber)
        let formattedInteger = formatGroupedInteger(integerDigits)

        if parts.count == 1 {
            return formattedInteger
        }

        let fractionalDigits = parts.dropFirst().joined().filter(\.isNumber)
        let limitedFraction = String(fractionalDigits.prefix(2))

        if normalized.hasSuffix(",") && limitedFraction.isEmpty {
            return formattedInteger + ","
        }

        return limitedFraction.isEmpty
            ? formattedInteger
            : formattedInteger + "," + limitedFraction
    }

    private func formatGroupedInteger(_ digits: String) -> String {
        guard !digits.isEmpty else { return "" }
        guard let number = Int(digits) else { return digits }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        return formatter.string(from: NSNumber(value: number)) ?? digits
    }

    private func formattedRubAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) ₽"
    }
}
