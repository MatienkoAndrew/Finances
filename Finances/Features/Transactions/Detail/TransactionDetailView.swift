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
    @State private var editedSubcategoryName: String?
    @State private var editedNote: String = ""
    @State private var editedFromAccount: Account?
    @State private var editedToAccount: Account?

    @State private var isShowingCurrencyPicker = false
    @State private var isShowingToCurrencyPicker = false
    @State private var isShowingCategoryPicker = false
    @State private var isShowingNoteEditor = false
    @State private var isShowingDeleteConfirmation = false

    private var settings: AppSettings? {
        settingsList.first
    }

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    var body: some View {
        Group {
            if isEditing {
                editForm
            } else {
                summaryView
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
        .sheet(isPresented: $showingTagPicker) {
            TagPickerView(transaction: transaction)
        }
        .alert("Заметка", isPresented: $isShowingNoteEditor) {
            TextField("Например, ужин с друзьями", text: $editedNote)
            Button("Сохранить") {
                let trimmed = editedNote.trimmingCharacters(in: .whitespacesAndNewlines)
                transaction.note = trimmed.isEmpty ? nil : trimmed
                try? modelContext.save()
            }
            Button("Отмена", role: .cancel) {
                editedNote = transaction.note ?? ""
            }
        }
        .confirmationDialog("Удалить транзакцию?", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                deleteTransaction()
            }
        }
        .sheet(isPresented: $isShowingCategoryPicker) {
            CategoryPickerSheet(
                categories: categories,
                initialCategory: editedCategoryName,
                initialSubcategory: editedSubcategoryName,
                subtitle: transaction.details
            ) { category, subcategory in
                editedCategoryName = category
                editedSubcategoryName = subcategory
                transaction.categoryName = category
                transaction.subcategoryName = subcategory
                // Явный выбор пользователем — помечаем как ручной, чтобы
                // массовое применение правил не затирало категорию.
                transaction.isCategoryManuallySet = true
                try? modelContext.save()
            }
        }
        .onAppear {
            syncEditedStateFromTransaction()
        }
    }

    private var categorySelectionLabel: String {
        let category = editedCategoryName ?? "Другое"
        if let sub = editedSubcategoryName, !sub.isEmpty {
            return "\(category) · \(sub)"
        }
        return category
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
        editedSubcategoryName = transaction.subcategoryName
        editedNote = transaction.note ?? ""
        editedFromAccount = transaction.fromAccount
        editedToAccount = transaction.toAccount
    }

    private func saveChanges() {
        guard let parsedAmount = parseNumber(editedAmountText) else { return }

        let editedCode = CurrencyDisplay.normalizedCode(from: editedCurrencyCode)
        // ₽-эквивалент меняется, только если поменялось то, от чего он зависит.
        let needsRubAmount = parsedAmount != transaction.amount
            || editedCode != CurrencyDisplay.normalizedCode(from: transaction.currencyCode)
            || !Calendar.current.isDate(editedDate, inSameDayAs: transaction.date)

        transaction.date = editedDate
        transaction.amount = parsedAmount
        transaction.currencyCode = CurrencyDisplay.normalizedCode(from: editedCurrencyCode)
        transaction.details = editedDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.categoryName = editedCategoryName
        transaction.subcategoryName = editedSubcategoryName
        // Сохранение через "Редактировать → Сохранить" — это явное подтверждение
        // категории пользователем. Помечаем как ручную, чтобы массовое
        // применение правил впредь не затирало её.
        transaction.isCategoryManuallySet = true

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

        if needsRubAmount {
            transaction.rubAmount = RubRateTable.load(context: modelContext)
                .rubAmount(amount: transaction.amount, currencyCode: transaction.currencyCode, on: transaction.date)
        }

        // Если пользователь сменил дату — операция могла попасть в период другой метки.
        // Не удаляем уже стоящие теги, только добавляем новые подходящие.
        TransactionTagSync.applyPeriodTags(to: transaction, allTags: allTags)

        try? modelContext.save()
        if needsRubAmount {
            Task { await ExchangeRateSync.shared.run(context: modelContext) }
        }
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
    
    // MARK: - Edit form

    private var editForm: some View {
        Form {
            Section("Основная информация") {
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
            }

            if transaction.kind == .expense {
                Section("Категория") {
                    Button {
                        isShowingCategoryPicker = true
                    } label: {
                        HStack {
                            Text("Категория")
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(categorySelectionLabel)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Заметка") {
                TextField("Заметка", text: $editedNote, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section("Счета") {
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
            }

            Section {
                Button("Удалить транзакцию", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
            }
        }
    }

    // MARK: - Summary

    @Query(sort: \TransactionTag.createdAt, order: .reverse)
    private var allTags: [TransactionTag]

    @State private var showingTagPicker = false

    private var categoryItem: ExpenseCategoryItem? {
        CategoryLookup.findCategory(named: transaction.categoryName, in: categories)
    }

    private var rubAmount: Double? {
        TransactionRubConverter.displayRubAmount(for: transaction, settings: settings, trackedRates: trackedRates)
    }

    /// Компактная карточка в стиле Alipay: сумма, учёт (категория, метки, заметка),
    /// редкие сведения (счёт, источник) — внизу мелко. Помещается на экран без прокрутки.
    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 12) {
                heroCard
                managementCard
                footerCard

                Button("Удалить транзакцию", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                .font(.subheadline)
                .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var heroCard: some View {
        VStack(spacing: 8) {
            heroIcon
                .padding(.bottom, 2)

            Text(transaction.details)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .textSelection(.enabled)

            Text(heroAmount)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(transaction.kind == .income ? Color.green : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let secondary = heroSecondaryAmounts {
                Text(secondary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text("\(formattedDate(transaction.date)) · \(transaction.kind.title)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private var heroIcon: some View {
        if transaction.kind == .expense, let categoryItem {
            CategoryIconView(category: categoryItem, size: 52)
        } else {
            Image(systemName: transaction.kind.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(transaction.kind == .income ? Color.green : Color.indigo, in: Circle())
        }
    }

    private var heroAmount: String {
        let sign: String
        switch transaction.kind {
        case .expense: sign = "−"
        case .income: sign = "+"
        case .transfer: sign = ""
        }

        if transaction.kind != .transfer, let rubAmount {
            return sign + formattedAmount(rubAmount, currency: "₽")
        }
        return sign + formattedAmount(transaction.amount, currency: CurrencyDisplay.symbol(for: transaction.currencyCode))
    }

    /// Сумма в валюте счёта и в валюте покупки: «2 637,16 ₸ · 8 000,00 ₩».
    private var heroSecondaryAmounts: String? {
        var parts: [String] = []

        if transaction.kind == .transfer {
            if transaction.isCrossCurrencyTransfer {
                parts.append("→ " + formattedAmount(
                    transaction.creditedAmount,
                    currency: CurrencyDisplay.symbol(for: transaction.creditedCurrencyCode)
                ))
            }
        } else {
            if rubAmount != nil, CurrencyDisplay.normalizedCode(from: transaction.currencyCode) != "RUB" {
                parts.append(formattedAmount(transaction.amount, currency: CurrencyDisplay.symbol(for: transaction.currencyCode)))
            }
            if let foreignAmount = transaction.foreignAmount, let foreignCode = transaction.foreignCurrencyCode {
                parts.append(formattedAmount(foreignAmount, currency: CurrencyDisplay.symbol(for: foreignCode)))
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var managementCard: some View {
        VStack(spacing: 0) {
            if transaction.kind == .expense {
                managementRow("Категория") {
                    isShowingCategoryPicker = true
                } value: {
                    CategoryChip(
                        category: categoryItem,
                        categoryName: transaction.categoryName ?? "Другое",
                        subcategoryName: transaction.subcategoryName,
                        showsChevron: false
                    )
                }

                Divider().padding(.leading, 16)
            }

            managementRow("Метки") {
                showingTagPicker = true
            } value: {
                tagsValue
            }

            Divider().padding(.leading, 16)

            managementRow("Заметка") {
                editedNote = transaction.note ?? ""
                isShowingNoteEditor = true
            } value: {
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    Text("Добавить")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private var tagsValue: some View {
        let names = transaction.tagNames ?? []

        if names.isEmpty {
            Text("Выбрать")
                .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 6) {
                ForEach(names.prefix(2), id: \.self) { name in
                    TagChip(name: name, tag: allTags.first { $0.name == name })
                }
                if names.count > 2 {
                    Text("+\(names.count - 2)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func managementRow<Value: View>(
        _ title: String,
        action: @escaping () -> Void,
        @ViewBuilder value: () -> Value
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                value()
                    .font(.subheadline)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footerCard: some View {
        VStack(spacing: 8) {
            footerRow("Счёт", accountSummary)

            if let source = transaction.sourceFileName {
                footerRow("Источник", source)
            }

            if let importedAt = transaction.importedAt {
                footerRow("Импортировано", formattedDateTime(importedAt))
            } else {
                footerRow("Создано", formattedDateTime(transaction.createdAt))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private var accountSummary: String {
        switch transaction.kind {
        case .expense:
            return transaction.fromAccount?.displayTitle ?? "—"
        case .income:
            return transaction.toAccount?.displayTitle ?? "—"
        case .transfer:
            return "\(transaction.fromAccount?.displayTitle ?? "—") → \(transaction.toAccount?.displayTitle ?? "—")"
        }
    }

    private func footerRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.footnote)
    }
}

/// Метка-капсула: иконка и название.
struct TagChip: View {
    let name: String
    let tag: TransactionTag?
    var isSelected = false

    private var color: Color {
        tag?.colorHex.flatMap { Color(hex: $0) } ?? .accentColor
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon = tag?.icon, !icon.isEmpty {
                if icon.unicodeScalars.first?.properties.isEmoji == true, icon.count <= 2 {
                    Text(icon)
                } else {
                    Image(systemName: icon)
                }
            } else {
                Image(systemName: "tag.fill")
            }

            Text(name)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isSelected ? .white : color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(isSelected ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.13)), in: Capsule())
    }
}

// MARK: - Tag Picker View

/// Выбор меток в стиле Alipay: выбранные сверху, ниже — все метки и «Новая».
struct TagPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TransactionTag.createdAt, order: .reverse)
    private var allTags: [TransactionTag]

    let transaction: Transaction

    @State private var selected: [String] = []
    @State private var isCreating = false
    @State private var newTagName = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    selectedCard
                    allTagsCard
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Button {
                    apply()
                } label: {
                    Text("Готово")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("Метки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color.gray.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Закрыть")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onAppear {
            selected = transaction.tagNames ?? []
        }
    }

    private var selectedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Выбранные")
                    .font(.headline)
                Spacer()
                Text("\(selected.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if selected.isEmpty {
                Text("Выбери метку ниже или создай новую")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(selected, id: \.self) { name in
                        Button {
                            toggle(name)
                        } label: {
                            HStack(spacing: 4) {
                                TagChip(name: name, tag: allTags.first { $0.name == name }, isSelected: true)
                            }
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white, .gray)
                                    .offset(x: 5, y: -5)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private var allTagsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Мои метки")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isCreating = true
                    }
                    isNameFocused = true
                } label: {
                    Label("Новая", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            if isCreating {
                HStack(spacing: 8) {
                    TextField("Название метки", text: $newTagName)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit(createTag)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color(.tertiarySystemFill), in: Capsule())

                    Button("Создать", action: createTag)
                        .font(.subheadline.weight(.semibold))
                        .disabled(trimmedNewName.isEmpty)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if allTags.isEmpty && !isCreating {
                Text("Меток пока нет")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(allTags) { tag in
                        Button {
                            toggle(tag.name)
                        } label: {
                            TagChip(name: tag.name, tag: tag, isSelected: selected.contains(tag.name))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private var trimmedNewName: String {
        newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggle(_ name: String) {
        withAnimation(.snappy(duration: 0.2)) {
            if let index = selected.firstIndex(of: name) {
                selected.remove(at: index)
            } else {
                selected.append(name)
            }
        }
    }

    private func createTag() {
        let name = trimmedNewName
        guard !name.isEmpty else { return }

        if !allTags.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            modelContext.insert(TransactionTag(name: name, icon: "🏷️", colorHex: "#007AFF"))
        }
        let existingName = allTags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.name ?? name
        if !selected.contains(existingName) {
            selected.append(existingName)
        }

        newTagName = ""
        withAnimation(.snappy(duration: 0.2)) {
            isCreating = false
        }
    }

    private func apply() {
        let current = transaction.tagNames ?? []
        // manual: true — явный выбор пользователя: снятые метки авто-теггер не вернёт,
        // добавленные вручную снова разрешены.
        for name in current where !selected.contains(name) {
            transaction.removeTag(name, manual: true)
        }
        for name in selected where !current.contains(name) {
            transaction.addTag(name, manual: true)
        }
        try? modelContext.save()
        dismiss()
    }
}

/// Раскладка «в строку с переносом» для капсул.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
