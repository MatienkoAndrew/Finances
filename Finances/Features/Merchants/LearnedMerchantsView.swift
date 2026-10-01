import SwiftUI
import SwiftData

/// Что приложение запомнило о мерчантах: правила из «применить ко всем», ручной выбор
/// у отдельных операций и догадки нейросети. Тап — сменить категорию для всех операций
/// мерчанта, свайп — забыть.
struct LearnedMerchantsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var categories: [ExpenseCategoryItem]
    @Query private var rules: [CategoryRule]
    @Query(filter: #Predicate<Transaction> { $0.kindRaw == "expense" }, sort: \Transaction.date, order: .reverse)
    private var expenses: [Transaction]

    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var editing: LearnedMerchant?
    /// Кэш нейросети не наблюдаемый — пересчитываем список вручную после изменений.
    @State private var revision = 0

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "Все"
        case mine = "Мои"
        case ai = "Нейросеть"
        var id: String { rawValue }
    }

    var body: some View {
        let _ = revision
        let all = LearnedMerchant.collect(expenses: expenses, rules: rules)
        let sections = sections(from: all)

        List {
            Section {
                Picker("Показать", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("Категории, которые ты выбрал сам, и догадки нейросети ✨. Нажми, чтобы сменить категорию у всех операций мерчанта, смахни — чтобы забыть.")
            }

            if sections.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Пока пусто" : "Ничего не найдено",
                    systemImage: searchText.isEmpty ? "brain" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                                      ? "Выбери категорию у операции — приложение запомнит мерчанта и будет ставить её само."
                                      : "Попробуй другое название.")
                )
                .listRowBackground(Color.clear)
            }

            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.merchants) { merchant in
                        Button {
                            editing = merchant
                        } label: {
                            LearnedMerchantRow(merchant: merchant, category: section.category)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Забыть", role: .destructive) { forget(merchant) }
                        }
                        .contextMenu {
                            Button {
                                editing = merchant
                            } label: {
                                Label("Сменить категорию", systemImage: "square.grid.2x2")
                            }
                            Button(role: .destructive) {
                                forget(merchant)
                            } label: {
                                Label("Забыть", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    LearnedMerchantSectionHeader(title: section.title, category: section.category, count: section.merchants.count)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Мерчант или категория")
        .navigationTitle("Запомненные мерчанты")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { merchant in
            CategoryPickerSheet(
                categories: categories,
                initialCategory: merchant.match.category,
                initialSubcategory: merchant.match.subcategory,
                subtitle: merchant.title
            ) { category, subcategory in
                guard let category else { return }
                change(merchant, to: CategoryMatch(category: category, subcategory: subcategory))
            }
        }
    }

    // MARK: - Sections

    private struct MerchantSection {
        let title: String
        let category: ExpenseCategoryItem?
        let merchants: [LearnedMerchant]
    }

    private func sections(from merchants: [LearnedMerchant]) -> [MerchantSection] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let visible = merchants.filter { merchant in
            switch filter {
            case .all: break
            case .mine: if merchant.source == .ai { return false }
            case .ai: if merchant.source != .ai { return false }
            }
            guard !query.isEmpty else { return true }
            return merchant.title.localizedCaseInsensitiveContains(query)
                || merchant.match.category.localizedCaseInsensitiveContains(query)
                || (merchant.match.subcategory?.localizedCaseInsensitiveContains(query) ?? false)
        }

        let grouped = Dictionary(grouping: visible) { CategoryNameNormalizer.normalize($0.match.category) }
        let order = ExpenseCategoryItem.ordered(categories)

        return grouped.values
            .map { merchants in
                let category = CategoryLookup.findCategory(named: merchants[0].match.category, in: categories)
                return MerchantSection(
                    title: category?.name ?? merchants[0].match.category,
                    category: category,
                    merchants: merchants.sorted {
                        $0.transactions.count != $1.transactions.count
                            ? $0.transactions.count > $1.transactions.count
                            : $0.title < $1.title
                    }
                )
            }
            .sorted { lhs, rhs in
                let left = lhs.category.flatMap { order.firstIndex(of: $0) } ?? Int.max
                let right = rhs.category.flatMap { order.firstIndex(of: $0) } ?? Int.max
                return left != right ? left < right : lhs.title < rhs.title
            }
    }

    // MARK: - Actions

    /// Новая категория для всех операций мерчанта и правило для будущих импортов —
    /// так же, как «применить ко всем» у операции.
    private func change(_ merchant: LearnedMerchant, to match: CategoryMatch) {
        for transaction in merchant.transactions {
            transaction.categoryName = match.category
            transaction.subcategoryName = match.subcategory
            transaction.isCategoryManuallySet = true
        }

        if merchant.rules.isEmpty {
            modelContext.insert(CategoryRule(
                pattern: merchant.rulePattern,
                categoryName: match.category,
                subcategoryName: match.subcategory,
                priority: 1
            ))
        } else {
            for rule in merchant.rules {
                rule.categoryName = match.category
                rule.subcategoryName = match.subcategory
            }
        }

        AIMerchantCategoryCache.remove(merchant.key)
        try? modelContext.save()
        revision += 1
    }

    /// Забыть мерчанта: операции сохраняют категорию, но новые больше не получат её автоматически.
    private func forget(_ merchant: LearnedMerchant) {
        for rule in merchant.rules {
            modelContext.delete(rule)
        }
        for transaction in merchant.transactions where transaction.isCategoryManuallySet == true {
            transaction.isCategoryManuallySet = false
        }
        AIMerchantCategoryCache.remove(merchant.key)
        try? modelContext.save()
        revision += 1
    }
}

// MARK: - Model

/// Запомненный мерчант и откуда взялась его категория.
struct LearnedMerchant: Identifiable {
    enum Source {
        /// Правило: «применить ко всем» у операции.
        case rule
        /// Пользователь выбрал категорию у отдельной операции.
        case manual
        /// Догадка нейросети.
        case ai
    }

    let key: String
    let title: String
    let match: CategoryMatch
    let source: Source
    let transactions: [Transaction]
    let rules: [CategoryRule]
    /// Паттерн для правила, если его ещё нет.
    let rulePattern: String

    var id: String { "\(source)|\(key)" }

    /// Собирает мерчантов в порядке, в котором категоризация их применяет:
    /// правила пользователя → ручной выбор → нейросеть. Кто уже покрыт более
    /// сильным источником, второй раз не показывается.
    static func collect(expenses: [Transaction], rules: [CategoryRule]) -> [LearnedMerchant] {
        var result: [LearnedMerchant] = []
        var seenKeys = Set<String>()

        // 1. Правила. Несколько правил с одним ключом («GRAB» и «grab») — одна строка.
        let activeRules = rules.filter {
            $0.isEnabled && !$0.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let rulePatterns = activeRules.map { $0.pattern.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        func ruleCovers(_ transaction: Transaction) -> Bool {
            let details = transaction.details.uppercased()
            return rulePatterns.contains { details.contains($0) }
        }

        let rulesByKey = Dictionary(grouping: activeRules) { rule in
            let key = MerchantName.key(rule.pattern)
            return key.isEmpty ? rule.pattern.uppercased() : key
        }
        for (key, group) in rulesByKey {
            let primary = group.max { $0.createdAt < $1.createdAt }!
            let patterns = group.map { $0.pattern.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            result.append(LearnedMerchant(
                key: key,
                title: primary.pattern.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                match: CategoryMatch(category: primary.categoryName, subcategory: primary.subcategoryName),
                source: .rule,
                transactions: expenses.filter { transaction in
                    let details = transaction.details.uppercased()
                    return patterns.contains { details.contains($0) }
                },
                rules: group,
                rulePattern: primary.pattern
            ))
            seenKeys.insert(key)
        }

        // 2. Ручной выбор у отдельных операций — последний выбор важнее.
        let byKey = Dictionary(grouping: expenses) { MerchantName.key($0.details) }
        for (key, group) in byKey where !key.isEmpty && !seenKeys.contains(key) {
            guard let latest = group.first(where: { $0.isCategoryManuallySet == true && $0.categoryName != nil }),
                  !ruleCovers(latest),
                  let category = latest.categoryName else { continue }

            result.append(LearnedMerchant(
                key: key,
                title: key,
                match: CategoryMatch(category: category, subcategory: latest.subcategoryName),
                source: .manual,
                transactions: group,
                rules: [],
                rulePattern: pattern(for: key, sample: latest.details)
            ))
            seenKeys.insert(key)
        }

        // 3. Нейросеть — если ни правило, ни ручной выбор, ни словарь этого мерчанта не знают.
        for (key, match) in AIMerchantCategoryCache.all where !seenKeys.contains(key) {
            guard CategoryNameNormalizer.normalize(match.category) != "другое" else { continue }
            let group = byKey[key] ?? []
            if let sample = group.first {
                guard !ruleCovers(sample),
                      ExpenseCategoryGuesser.guesses(for: "", details: sample.details).isEmpty else { continue }
            }

            result.append(LearnedMerchant(
                key: key,
                title: key,
                match: match,
                source: .ai,
                transactions: group,
                rules: [],
                rulePattern: pattern(for: key, sample: group.first?.details ?? key)
            ))
        }

        return result
    }

    /// Название без номера точки, если оно входит в строку выписки, — как у «применить ко всем».
    private static func pattern(for key: String, sample: String) -> String {
        let details = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.count >= 3 && details.uppercased().contains(key) ? key : details
    }
}

// MARK: - Rows

private struct LearnedMerchantRow: View {
    let merchant: LearnedMerchant
    let category: ExpenseCategoryItem?

    private var color: Color { category.flatMap { Color(hex: $0.colorHex) } ?? .gray }

    private var subcategoryEmoji: String? {
        guard let name = merchant.match.subcategory else { return nil }
        return DefaultSubcategoryDefinitions.subcategories(for: merchant.match.category)?
            .first { $0.name == name }?.emoji
    }

    private var subtitle: String {
        let count = merchant.transactions.count
        let operations = count == 0 ? "нет операций" : "\(count) \(Self.operationsWord(count))"
        if let subcategory = merchant.match.subcategory {
            return "\(subcategory) · \(operations)"
        }
        return operations
    }

    private static func operationsWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "операция" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "операции" }
        return "операций"
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 38, height: 38)
                .overlay {
                    if let subcategoryEmoji {
                        Text(subcategoryEmoji)
                            .font(.system(size: 18))
                    } else if let category, let emoji = category.emoji, !emoji.isEmpty {
                        Text(emoji)
                            .font(.system(size: 18))
                    } else {
                        Image(systemName: category?.iconName ?? "questionmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(color)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(merchant.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if merchant.source == .ai {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                    .frame(width: 26, height: 26)
                    .background(Color.purple.opacity(0.12), in: Circle())
                    .accessibilityLabel("Догадка нейросети")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct LearnedMerchantSectionHeader: View {
    let title: String
    let category: ExpenseCategoryItem?
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            if let category {
                CategoryIconView(category: category, size: 20)
            }
            Text(title)
            Spacer()
            Text("\(count)")
                .monospacedDigit()
        }
        .font(.footnote.weight(.semibold))
        .textCase(nil)
    }
}
