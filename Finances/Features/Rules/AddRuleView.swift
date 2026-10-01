import SwiftUI
import SwiftUI
import SwiftData

struct AddRuleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @Query(sort: \CategoryRule.priority, order: .reverse)
    private var existingRules: [CategoryRule]

    @State private var pattern: String = ""
    @State private var selectedCategoryName: String = "Другое"
    @State private var selectedPriority: PriorityLevel = .medium

    @State private var resultMessage: String?
    @State private var isShowingResultAlert = false
    @State private var isShowingSavePrompt = false
    @State private var pendingRuleToSave: CategoryRule?

    @State private var visibleCount: Int = 8

    @FocusState private var isPatternFocused: Bool

    // MARK: - Computed

    private var trimmedPattern: String {
        pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedPattern: String {
        trimmedPattern.uppercased()
    }

    private var expenseTransactions: [Transaction] {
        transactions.filter { $0.kind == .expense }
    }

    private var matchingTransactions: [Transaction] {
        guard !normalizedPattern.isEmpty else { return [] }

        return expenseTransactions.filter {
            $0.details.uppercased().contains(normalizedPattern)
        }
    }

    private var selectedCategoryItem: ExpenseCategoryItem? {
        CategoryLookup.findCategory(named: selectedCategoryName, in: categories)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        conditionCard
                        categoryCard
                        priorityCard
                        actionsCard
                        previewCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Новое правило")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
            .alert("Готово", isPresented: $isShowingResultAlert) {
                Button("OK") {
                    if pendingRuleToSave != nil {
                        isShowingSavePrompt = true
                    } else {
                        dismiss()
                    }
                }
            } message: {
                Text(resultMessage ?? "")
            }
            .confirmationDialog(
                "Сохранить правило?",
                isPresented: $isShowingSavePrompt
            ) {
                Button("Сохранить") {
                    savePendingRule()
                }

                Button("Нет", role: .cancel) {
                    dismiss()
                }
            }
            .onChange(of: pattern) { _, _ in
                visibleCount = 8
            }
            .onAppear {
                if categories.contains(where: { $0.name == "Другое" }) == false,
                   let first = categories.first {
                    selectedCategoryName = first.name
                }
            }
        }
    }

    // MARK: - UI

    private var conditionCard: some View {
        TextField("Например: КОМИССИЯ", text: $pattern)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .focused($isPatternFocused)
            .font(.headline)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }

    private var categoryCard: some View {
        HStack {
            Spacer()

            Menu {
                ForEach(categories) { category in
                    Button {
                        selectedCategoryName = category.name
                    } label: {
                        Label(category.name, systemImage: category.iconName)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if let selectedCategoryItem {
                        Circle()
                            .fill(Color(hex: selectedCategoryItem.colorHex) ?? .gray)
                            .frame(width: 20, height: 20)
                            .overlay {
                                Image(systemName: selectedCategoryItem.iconName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white)
                            }
                    }

                    Text(selectedCategoryName)
                        .font(.subheadline)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
        .onChange(of: selectedCategoryName) { _, newValue in
            // ничего не сохраняем сразу — только после apply
        }
    }

    private var priorityCard: some View {
        Picker("", selection: $selectedPriority) {
            ForEach(PriorityLevel.allCases) { level in
                Text(level.title).tag(level)
            }
        }
        .pickerStyle(.segmented)
    }

    private var actionsCard: some View {
        Button {
            applyNow()
        } label: {
            HStack {
                Spacer()
                Text("Применить")
                    .font(.headline)
                Spacer()
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .disabled(trimmedPattern.isEmpty || matchingTransactions.isEmpty)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Совпадения")
                    .font(.headline)

                Spacer()

                Text("\(matchingTransactions.count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.1))
                    )
            }
            
            // Показываем, сколько реально изменится с учетом приоритетов
            if !matchingTransactions.isEmpty, let willChangeCount = calculateWillChangeCount() {
                if willChangeCount != matchingTransactions.count {
                    Text("С учетом приоритетов будет изменено: \(willChangeCount)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if matchingTransactions.isEmpty {
                Text("Нет совпадений")
                    .foregroundStyle(.secondary)
            } else {
                let isLarge = matchingTransactions.count > 50
                let displayed = Array(matchingTransactions.prefix(visibleCount))

                VStack(spacing: 8) {
                    ForEach(displayed.indices, id: \.self) { index in
                        let tx = displayed[index]

                        previewRow(transaction: tx)
                            .onAppear {
                                if isLarge && index == displayed.count - 1 {
                                    loadMore()
                                }
                            }
                    }
                }

                // маленькие списки → кнопка
                if !isLarge && visibleCount < matchingTransactions.count {
                    Button("Показать все (\(matchingTransactions.count))") {
                        withAnimation(.spring()) {
                            visibleCount = matchingTransactions.count
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // большой список → индикатор
                if isLarge && visibleCount < matchingTransactions.count {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                if visibleCount > 8 {
                    Button("Свернуть") {
                        withAnimation(.spring()) {
                            visibleCount = 8
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
    }

    private func previewRow(transaction: Transaction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.details)
                    .font(.subheadline)

                Text(transaction.date, format: .dateTime.day().month())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("→ \(selectedCategoryName)")
                .font(.caption.bold())
                .foregroundStyle(.green)
        }
    }

    // MARK: - Logic

    private func calculateWillChangeCount() -> Int? {
        guard !trimmedPattern.isEmpty else { return nil }
        
        let transientRule = CategoryRule(
            pattern: trimmedPattern,
            categoryName: selectedCategoryName,
            priority: selectedPriority.rawValue,
            isEnabled: true
        )
        
        var count = 0
        let allRulesIncludingNew = existingRules + [transientRule]
        
        for transaction in matchingTransactions {
            let winningCategory = CategoryRuleEngine.matchCategoryName(
                operationType: transaction.ruleOperationType,
                details: transaction.details,
                rules: allRulesIncludingNew,
                existingCategories: categories
            )
            
            if winningCategory == selectedCategoryName,
               transaction.categoryName != selectedCategoryName {
                count += 1
            }
        }
        
        return count
    }

    private func loadMore() {
        guard visibleCount < matchingTransactions.count else { return }

        withAnimation(.spring()) {
            visibleCount += 10
        }
    }

    private func applyNow() {
        let transientRule = CategoryRule(
            pattern: trimmedPattern,
            categoryName: selectedCategoryName,
            priority: selectedPriority.rawValue,
            isEnabled: true
        )

        // Подсчитаем, сколько транзакций изменит ИМЕННО наше новое правило
        // с учетом приоритетов всех правил
        var newRuleMatchCount = 0
        let normalizedPattern = transientRule.pattern.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        for transaction in transactions where transaction.kind == .expense {
            guard transaction.details.uppercased().contains(normalizedPattern) else { continue }
            
            // Проверяем, что новое правило будет применено (учитывая приоритеты)
            let allRulesIncludingNew = existingRules + [transientRule]
            let winningCategory = CategoryRuleEngine.matchCategoryName(
                operationType: transaction.ruleOperationType,
                details: transaction.details,
                rules: allRulesIncludingNew,
                existingCategories: categories
            )
            
            // Если побеждает наше правило И категория отличается от текущей
            if winningCategory == selectedCategoryName,
               transaction.categoryName != selectedCategoryName {
                newRuleMatchCount += 1
            }
        }

        // Применяем ВСЕ правила, включая новое
        // Это гарантирует, что другие транзакции не потеряют свои категории
        var allRules = existingRules
        allRules.append(transientRule)
        
        let totalUpdatedCount = TransactionCategorySync.autoCategorizeTransactions(
            transactions,
            rules: allRules,
            categories: categories,
            overwriteExisting: true
        )

        try? modelContext.save()

        pendingRuleToSave = transientRule

        // Показываем количество изменений от нашего правила и общее количество
        if newRuleMatchCount == 0 {
            resultMessage = "Новое правило не изменило ни одной транзакции.\nВсего обновлено: \(totalUpdatedCount)"
        } else if newRuleMatchCount == totalUpdatedCount {
            resultMessage = "Применено к \(newRuleMatchCount) транзакциям"
        } else {
            resultMessage = "Новое правило применено к \(newRuleMatchCount) транзакциям.\nВсего обновлено (со всеми правилами): \(totalUpdatedCount)"
        }

        isShowingResultAlert = true
    }

    private func savePendingRule() {
        guard let rule = pendingRuleToSave else {
            dismiss()
            return
        }

        modelContext.insert(rule)
        try? modelContext.save()

        dismiss()
    }
}
