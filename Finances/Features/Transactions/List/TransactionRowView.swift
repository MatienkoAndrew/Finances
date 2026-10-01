import SwiftUI
import SwiftData

struct TransactionRowView: View {
    @Environment(\.modelContext) private var modelContext

    let transaction: Transaction

    @Query
    private var settingsList: [AppSettings]

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @State private var isShowingCategoryPicker = false
    @State private var pickedCategory: CategoryMatch?
    @State private var pendingCategoryChange: PendingCategoryChange? = nil

    private struct PendingCategoryChange: Identifiable {
        let id = UUID()
        let categoryName: String
        let subcategoryName: String?
        let matchingCount: Int

        var title: String {
            subcategoryName.map { "\(categoryName) · \($0)" } ?? categoryName
        }
    }

    private var settings: AppSettings? {
        settingsList.first
    }

    private var categoryItem: ExpenseCategoryItem? {
        CategoryLookup.findCategory(named: transaction.categoryName, in: categories)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topRow

            if let text = secondaryAmountsText {
                secondaryAmountsRow(text: text)
            }

            metaRow

            if let note = transaction.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .confirmationDialog(
            confirmationDialogTitle,
            isPresented: Binding(
                get: { pendingCategoryChange != nil },
                set: { if !$0 { pendingCategoryChange = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pending = pendingCategoryChange {
                Button("Применить ко всем \(pending.matchingCount) транзакциям") {
                    applyToAll(categoryName: pending.categoryName, subcategoryName: pending.subcategoryName)
                }
                Button("Только эта транзакция") {
                    applySingle(categoryName: pending.categoryName, subcategoryName: pending.subcategoryName)
                }
                Button("Отмена", role: .cancel) {
                    pendingCategoryChange = nil
                }
            }
        } message: {
            if let pending = pendingCategoryChange {
                Text("Найдено ещё \(pending.matchingCount - 1) \(pluralTransactions(pending.matchingCount - 1)) от «\(MerchantName.key(transaction.details))». Назначить «\(pending.title)» всем? Новые операции этого места тоже получат эту категорию.")
            }
        }
    }

    private var confirmationDialogTitle: String {
        guard let pending = pendingCategoryChange else { return "" }
        return "Применить «\(pending.title)» ко всем?"
    }

    private func pluralTransactions(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 14 { return "транзакций" }
        if mod10 == 1 { return "транзакция" }
        if mod10 >= 2 && mod10 <= 4 { return "транзакции" }
        return "транзакций"
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(transaction.details)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                categoryMenu
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                Text(primaryAmountText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(primaryAmountColor)
                    .multilineTextAlignment(.trailing)

                Text(transaction.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func secondaryAmountsRow(text: String) -> some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(secondaryAmountColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()
        }
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            Image(systemName: metaIconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(metaIconColor)

            Text(accountLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
    }

    @ViewBuilder
    private var categoryMenu: some View {
        if transaction.kind == .expense {
            Button {
                isShowingCategoryPicker = true
            } label: {
                CategoryChip(
                    category: categoryItem,
                    categoryName: transaction.categoryName ?? "Другое",
                    subcategoryName: transaction.subcategoryName
                )
            }
            .buttonStyle(.borderless)
            .sheet(isPresented: $isShowingCategoryPicker, onDismiss: applyPickedCategory) {
                CategoryPickerSheet(
                    categories: categories,
                    initialCategory: transaction.categoryName,
                    initialSubcategory: transaction.subcategoryName,
                    subtitle: transaction.details
                ) { category, subcategory in
                    pickedCategory = category.map { CategoryMatch(category: $0, subcategory: subcategory) }
                }
            }
        }
    }

    /// Выбор применяем после закрытия шторки: иначе вопрос «применить ко всем?» не успевает показаться.
    private func applyPickedCategory() {
        guard let picked = pickedCategory else { return }
        pickedCategory = nil
        updateCategory(picked.category, subcategory: picked.subcategory)
    }

    private var resolvedRubAmount: Double? {
        TransactionRubConverter.displayRubAmount(
            for: transaction,
            settings: settings,
            trackedRates: trackedRates
        )
    }

    private var primaryAmountText: String {
        switch transaction.kind {
        case .expense, .income:
            if let rub = resolvedRubAmount {
                return signedFormattedAmount(
                    rub,
                    currency: "₽",
                    kind: transaction.kind
                )
            } else {
                return signedFormattedAmount(
                    transaction.amount,
                    currency: CurrencyDisplay.normalizedCode(from: transaction.currencyCode),
                    kind: transaction.kind
                )
            }

        case .transfer:
            if transaction.isCrossCurrencyTransfer {
                return formattedUnsignedAmount(
                    transaction.creditedAmount,
                    currency: CurrencyDisplay.normalizedCode(from: transaction.creditedCurrencyCode)
                )
            } else {
                return formattedUnsignedAmount(
                    transaction.amount,
                    currency: CurrencyDisplay.normalizedCode(from: transaction.currencyCode)
                )
            }
        }
    }

    private var secondaryAmountsText: String? {
        switch transaction.kind {
        case .expense, .income:
            var parts: [String] = []

            if let foreignAmount = transaction.foreignAmount,
               let foreignCurrencyCode = transaction.foreignCurrencyCode {
                parts.append(
                    signedFormattedAmount(
                        foreignAmount,
                        currency: CurrencyDisplay.normalizedCode(from: foreignCurrencyCode),
                        kind: transaction.kind
                    )
                )
            }

            if resolvedRubAmount != nil || transaction.foreignAmount != nil {
                parts.append(
                    signedFormattedAmount(
                        transaction.amount,
                        currency: CurrencyDisplay.normalizedCode(from: transaction.currencyCode),
                        kind: transaction.kind
                    )
                )
            }

            return parts.isEmpty ? nil : parts.joined(separator: " • ")

        case .transfer:
            if transaction.isCrossCurrencyTransfer {
                return "\(formattedUnsignedAmount(transaction.amount, currency: CurrencyDisplay.normalizedCode(from: transaction.currencyCode))) → \(formattedUnsignedAmount(transaction.creditedAmount, currency: CurrencyDisplay.normalizedCode(from: transaction.creditedCurrencyCode)))"
            } else {
                return nil
            }
        }
    }

    private var accountLine: String {
        switch transaction.kind {
        case .expense:
            return transaction.fromAccount?.name ?? "Без счета"

        case .income:
            return transaction.toAccount?.name ?? "Без счета"

        case .transfer:
            let from = transaction.fromAccount?.name ?? "Без счета"
            let to = transaction.toAccount?.name ?? "Без счета"
            return "\(from) → \(to)"
        }
    }

    private var primaryAmountColor: Color {
        switch transaction.kind {
        case .expense:
            return .red
        case .income:
            return .green
        case .transfer:
            return .primary
        }
    }

    private var secondaryAmountColor: Color {
        switch transaction.kind {
        case .expense:
            return .red.opacity(0.75)
        case .income:
            return .green.opacity(0.75)
        case .transfer:
            return .secondary
        }
    }

    private var metaIconName: String {
        switch transaction.kind {
        case .expense:
            return "arrow.up.circle.fill"
        case .income:
            return "arrow.down.circle.fill"
        case .transfer:
            return "arrow.left.arrow.right.circle.fill"
        }
    }

    private var metaIconColor: Color {
        switch transaction.kind {
        case .expense:
            return .red.opacity(0.75)
        case .income:
            return .green.opacity(0.75)
        case .transfer:
            return .secondary
        }
    }

    /// Точка входа при выборе категории.
    /// Если есть другие операции того же места — предлагаем применить ко всем.
    private func updateCategory(_ name: String, subcategory: String?) {
        let allMatching = sameMerchantTransactions()
        let otherCount = allMatching.filter { $0.persistentModelID != transaction.persistentModelID }.count

        if otherCount > 0 {
            // Есть ещё похожие — показываем шаг подтверждения
            pendingCategoryChange = PendingCategoryChange(
                categoryName: name,
                subcategoryName: subcategory,
                matchingCount: allMatching.count
            )
        } else {
            // Единственная такая транзакция — меняем без лишних вопросов
            applySingle(categoryName: name, subcategoryName: subcategory)
        }
    }

    /// Расходы того же мерчанта: номер точки и префикс агрегатора не важны
    /// («PAYOO MCDONALDS 0053A» и «PAYOO MCDONALDS 0017B»).
    private func sameMerchantTransactions() -> [Transaction] {
        let key = MerchantName.key(transaction.details)
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.kindRaw == "expense" }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { MerchantName.key($0.details) == key }
    }

    /// Применяет категорию только к текущей транзакции.
    private func applySingle(categoryName: String, subcategoryName: String?) {
        transaction.categoryName = categoryName
        transaction.subcategoryName = subcategoryName
        transaction.isCategoryManuallySet = true
        try? modelContext.save()
        pendingCategoryChange = nil
    }

    /// Применяет категорию ко всем операциям того же места и создаёт правило для будущих импортов.
    private func applyToAll(categoryName: String, subcategoryName: String?) {
        // 1. Обновляем все совпадающие транзакции
        for t in sameMerchantTransactions() {
            t.categoryName = categoryName
            t.subcategoryName = subcategoryName
            t.isCategoryManuallySet = true
        }

        // 2. Создаём правило, чтобы будущие импорты категоризировались автоматически.
        // Паттерн — название без номера точки, если оно входит в исходную строку.
        let details = transaction.details.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = MerchantName.key(details)
        let pattern = key.count >= 3 && details.uppercased().contains(key) ? key : details
        let rulesDescriptor = FetchDescriptor<CategoryRule>(
            predicate: #Predicate { $0.pattern == pattern }
        )
        let existingRules = (try? modelContext.fetch(rulesDescriptor)) ?? []
        if let rule = existingRules.first {
            // Правило уже есть — обновляем категорию
            rule.categoryName = categoryName
            rule.subcategoryName = subcategoryName
        } else {
            modelContext.insert(CategoryRule(
                pattern: pattern,
                categoryName: categoryName,
                subcategoryName: subcategoryName,
                priority: 1
            ))
        }

        try? modelContext.save()
        pendingCategoryChange = nil
    }

    private func signedFormattedAmount(
        _ value: Double,
        currency: String,
        kind: TransactionKind
    ) -> String {
        let sign: String
        switch kind {
        case .expense:
            sign = "-"
        case .income:
            sign = "+"
        case .transfer:
            sign = ""
        }

        let number = formattedNumber(abs(value))
        return sign.isEmpty ? "\(number) \(currency)" : "\(sign) \(number) \(currency)"
    }

    private func formattedUnsignedAmount(
        _ value: Double,
        currency: String
    ) -> String {
        "\(formattedNumber(abs(value))) \(currency)"
    }

    private func formattedNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        return formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
    }
}
