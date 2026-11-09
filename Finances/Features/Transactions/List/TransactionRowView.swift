import SwiftUI
import SwiftData

/// Справочники для строк операций: категории (плашка и выбор категории) и курсы —
/// на случай, если у операции ещё нет суммы в рублях.
///
/// Раньше каждая строка запрашивала их из базы сама: три запроса на строку при
/// каждом её появлении в списке и повторно после каждого сохранения. Теперь их
/// один раз собирает `RootTabView` и раздаёт строкам через окружение.
struct TransactionRowLookup: Equatable {
    var categories: [ExpenseCategoryItem] = []
    var settings: AppSettings?
    var trackedRates: [TrackedExchangeRate] = []
    /// Метки — для капсул в строках и заголовках дней.
    var tags: [TransactionTag] = []

    func tag(named name: String) -> TransactionTag? {
        tags.first { $0.name == name }
    }

    /// Сравнение по составу: правки самих категорий и курсов строки и так
    /// получают через наблюдение за моделями, а лишние перерисовки всех строк
    /// при каждом обновлении корневого экрана не нужны.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.categories.map(\.persistentModelID) == rhs.categories.map(\.persistentModelID)
            && lhs.settings?.persistentModelID == rhs.settings?.persistentModelID
            && lhs.trackedRates.map(\.persistentModelID) == rhs.trackedRates.map(\.persistentModelID)
            && lhs.tags.map(\.persistentModelID) == rhs.tags.map(\.persistentModelID)
    }
}

extension EnvironmentValues {
    @Entry var transactionRowLookup = TransactionRowLookup()
}

struct TransactionRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.transactionRowLookup) private var lookup

    let transaction: Transaction
    /// Дата в подписи — для списков без разбивки по дням.
    var showsDate = false
    /// Метки, которые уже видны выше (в заголовке дня, на экране метки), — в строке не повторяются.
    var hiddenTagNames: Set<String> = []

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

    private var categoryItem: ExpenseCategoryItem? {
        CategoryLookup.findCategory(named: transaction.categoryName, in: lookup.categories)
    }

    private static let iconSize: CGFloat = 38

    var body: some View {
        HStack(spacing: 12) {
            leadingIcon

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(transaction.details)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(primaryAmountText)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(primaryAmountColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    subtitle
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let tagName = visibleTagNames.first {
                        HStack(spacing: 4) {
                            TagChip(name: tagName, tag: lookup.tag(named: tagName), isCompact: true)

                            if visibleTagNames.count > 1 {
                                Text("+\(visibleTagNames.count - 1)")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .fixedSize()
                    }

                    Spacer(minLength: 8)

                    if let secondaryAmountText {
                        Text(secondaryAmountText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }

                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $isShowingCategoryPicker, onDismiss: applyPickedCategory) {
            CategoryPickerSheet(
                categories: lookup.categories,
                initialCategory: transaction.categoryName,
                initialSubcategory: transaction.subcategoryName,
                subtitle: transaction.details
            ) { category, subcategory in
                pickedCategory = category.map { CategoryMatch(category: $0, subcategory: subcategory) }
            }
        }
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

    /// Слева — иконка: у расхода это категория, и касание по ней меняет категорию.
    @ViewBuilder
    private var leadingIcon: some View {
        switch transaction.kind {
        case .expense:
            Button {
                isShowingCategoryPicker = true
            } label: {
                AnalyticsCategoryIcon(category: categoryItem, size: Self.iconSize)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Категория: \(categoryTitle). Сменить")

        case .income:
            SettingsIcon(systemImage: "arrow.down", color: .green, size: Self.iconSize)

        case .transfer:
            SettingsIcon(systemImage: "arrow.left.arrow.right", color: .gray, size: Self.iconSize)
        }
    }

    /// Выбор применяем после закрытия шторки: иначе вопрос «применить ко всем?» не успевает показаться.
    private func applyPickedCategory() {
        guard let picked = pickedCategory else { return }
        pickedCategory = nil
        updateCategory(picked.category, subcategory: picked.subcategory)
    }

    /// Метки операции, кроме уже показанных выше.
    private var visibleTagNames: [String] {
        (transaction.tagNames ?? []).filter { !hiddenTagNames.contains($0) }
    }

    /// Подкатегория точнее категории, а сама категория и так видна по иконке.
    private var categoryTitle: String {
        transaction.subcategoryName ?? transaction.categoryName ?? "Другое"
    }

    /// Вторая строка: категория и счёт, у перевода — откуда и куда.
    private var subtitle: Text {
        var parts: [String] = []

        if showsDate {
            // Даты в приложении — по-русски, как бы ни был настроен телефон.
            let isThisYear = Calendar.current.isDate(transaction.date, equalTo: .now, toGranularity: .year)
            let style = Date.FormatStyle(locale: Locale(identifier: "ru_RU")).day().month(.abbreviated)
            parts.append(transaction.date.formatted(isThisYear ? style : style.year()))
        }

        switch transaction.kind {
        case .expense:
            parts.append(categoryTitle)
            if let account = transaction.fromAccount?.name {
                parts.append(account)
            }

        case .income:
            if let category = transaction.categoryName, !category.isEmpty {
                parts.append(category)
            }
            parts.append(transaction.toAccount?.name ?? "Без счета")

        case .transfer:
            let from = transaction.fromAccount?.name ?? "Без счета"
            let to = transaction.toAccount?.name ?? "Без счета"
            parts.append("\(from) → \(to)")
        }

        let text = Text(parts.joined(separator: " · "))

        // Оплата из Apple Pay, которую ещё не сверили с выпиской.
        guard transaction.isAwaitingStatement else { return text }
        return Text(Image(systemName: "clock")) + Text(" ") + text
    }

    private var resolvedRubAmount: Double? {
        TransactionRubConverter.displayRubAmount(
            for: transaction,
            settings: lookup.settings,
            trackedRates: lookup.trackedRates
        )
    }

    /// Справа — сумма в рублях со знаком; если рублей ещё нет, то в валюте счёта.
    private var primaryAmountText: String {
        switch transaction.kind {
        case .expense, .income:
            if let rub = resolvedRubAmount {
                return signedAmount(rub, currencyCode: "RUB")
            }
            return signedAmount(transaction.amount, currencyCode: transaction.currencyCode)

        case .transfer:
            if transaction.isCrossCurrencyTransfer {
                return Self.amount(transaction.creditedAmount, currencyCode: transaction.creditedCurrencyCode)
            }
            return Self.amount(transaction.amount, currencyCode: transaction.currencyCode)
        }
    }

    /// Под суммой — сумма в валюте покупки: за границей это валюта страны,
    /// иначе валюта счёта. Списание со счёта при покупке за границей — на экране операции.
    private var secondaryAmountText: String? {
        switch transaction.kind {
        case .expense, .income:
            if let foreignAmount = transaction.foreignAmount,
               let foreignCurrencyCode = transaction.foreignCurrencyCode {
                return Self.amount(foreignAmount, currencyCode: foreignCurrencyCode)
            }

            let isRub = CurrencyDisplay.normalizedCode(from: transaction.currencyCode) == "RUB"
            guard resolvedRubAmount != nil, !isRub else { return nil }
            return Self.amount(transaction.amount, currencyCode: transaction.currencyCode)

        case .transfer:
            guard transaction.isCrossCurrencyTransfer else { return nil }
            return Self.amount(transaction.amount, currencyCode: transaction.currencyCode)
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

    private func signedAmount(_ value: Double, currencyCode: String) -> String {
        let sign: String
        switch transaction.kind {
        case .expense:
            sign = "−"
        case .income:
            sign = "+"
        case .transfer:
            sign = ""
        }
        return sign + Self.amount(value, currencyCode: currencyCode)
    }

    /// Сумма с символом валюты; копейки — только если они есть.
    @MainActor private static func amount(_ value: Double, currencyCode: String) -> String {
        let value = abs(value)
        let isWhole = (value * 100).rounded() == (value.rounded() * 100)
        let formatter = isWhole ? wholeFormatter : fractionFormatter
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) \(symbol(for: currencyCode))"
    }

    /// Короткий знак валюты: ₽, ₸, $, ₫. У рубля и тенге системные форматтеры
    /// вместо знака дают буквенный код, поэтому их знаки заданы явно.
    private static func symbol(for currencyCode: String) -> String {
        let code = CurrencyDisplay.normalizedCode(from: currencyCode)
        if let cached = symbolCache[code] { return cached }
        if let fixed = fixedSymbols[code] { return fixed }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.currencyCode = code
        let symbol = formatter.currencySymbol ?? code
        symbolCache[code] = symbol
        return symbol
    }

    @MainActor private static var symbolCache: [String: String] = [:]
    private static let fixedSymbols = ["RUB": "₽", "KZT": "₸"]

    // Форматтеры — одни на все строки: создавать их на каждую сумму дорого.
    private static let wholeFormatter = makeFormatter(fractionDigits: 0)
    private static let fractionFormatter = makeFormatter(fractionDigits: 2)

    private static func makeFormatter(fractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","
        return formatter
    }
}
