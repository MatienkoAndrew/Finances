import SwiftUI
import SwiftData

struct RulesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query(sort: \CategoryRule.priority, order: .reverse)
    private var rules: [CategoryRule]

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @State private var isShowingAddRule = false
    @State private var isShowingApplyRulesDialog = false
    @State private var applyRulesResultMessage: String?

    private var expenseTransactions: [Transaction] {
        transactions.filter { $0.kind == .expense }
    }

    var body: some View {
        NavigationStack {
            Group {
                if rules.isEmpty {
                    ContentUnavailableView(
                        "Нет правил",
                        systemImage: "wand.and.stars",
                        description: Text("Добавь первое правило для автоматической категоризации транзакций.")
                    )
                } else {
                    List {
                        Section {
                            Button {
                                isShowingApplyRulesDialog = true
                            } label: {
                                Label("Применить правила к транзакциям", systemImage: "wand.and.stars")
                            }
                            .confirmationDialog(
                                "Как применить правила?",
                                isPresented: $isShowingApplyRulesDialog,
                                titleVisibility: .visible
                            ) {
                                Button("Применить к пустым категориям") {
                                    let updatedCount = TransactionCategorySync.autoCategorizeTransactions(
                                        transactions,
                                        rules: rules,
                                        categories: categories,
                                        overwriteExisting: false
                                    )

                                    try? modelContext.save()

                                    applyRulesResultMessage = updatedCount == 0
                                        ? "Правила не изменили ни одной транзакции."
                                        : "Обновлено \(updatedCount) транзакций."
                                }

                                Button("Переприменить ко всем (кроме ручных)", role: .destructive) {
                                    let updatedCount = TransactionCategorySync.autoCategorizeTransactions(
                                        transactions,
                                        rules: rules,
                                        categories: categories,
                                        overwriteExisting: true
                                    )

                                    try? modelContext.save()

                                    applyRulesResultMessage = updatedCount == 0
                                        ? "Правила не изменили ни одной транзакции."
                                        : "Обновлено \(updatedCount) транзакций."
                                }

                                Button("Отмена", role: .cancel) { }
                            }
                        }

                        ForEach(rules) { rule in
                            NavigationLink {
                                RuleDetailView(rule: rule)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(rule.pattern)
                                            .font(.headline)

                                        HStack(spacing: 6) {
                                            Text("Назначит:")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)

                                            if let categoryItem = CategoryLookup.findCategory(named: rule.categoryName, in: categories) {
                                                HStack(spacing: 6) {
                                                    Circle()
                                                        .fill(Color(hex: categoryItem.colorHex) ?? .gray)
                                                        .frame(width: 16, height: 16)
                                                        .overlay {
                                                            Image(systemName: categoryItem.iconName)
                                                                .font(.system(size: 8, weight: .bold))
                                                                .foregroundStyle(.white)
                                                        }

                                                    Text(rule.categoryName)
                                                }
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                            } else {
                                                Text(rule.categoryName)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        Text(currentCategorySummary(for: rule))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        HStack(spacing: 8) {
                                            Text("Приоритет: \(PriorityLevel.from(rule.priority).title)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            Text(rule.isEnabled ? "Активно" : "Выключено")
                                                .font(.caption)
                                                .foregroundStyle(rule.isEnabled ? .green : .secondary)

                                            Text("Совпадений: \(matchCount(for: rule))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    rule.isEnabled.toggle()
                                    try? modelContext.save()
                                } label: {
                                    Label(
                                        rule.isEnabled ? "Выключить" : "Включить",
                                        systemImage: rule.isEnabled ? "pause.circle" : "play.circle"
                                    )
                                }
                                .tint(rule.isEnabled ? .orange : .green)
                            }
                        }
                        .onDelete(perform: deleteRules)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Правила")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddRule = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddRule) {
                AddRuleView()
            }
            .alert(
                "Готово",
                isPresented: Binding(
                    get: { applyRulesResultMessage != nil },
                    set: { if !$0 { applyRulesResultMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    applyRulesResultMessage = nil
                }
            } message: {
                Text(applyRulesResultMessage ?? "")
            }
        }
    }

    private func matchCount(for rule: CategoryRule) -> Int {
        guard rule.isEnabled else { return 0 }

        let normalizedPattern = rule.pattern
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalizedPattern.isEmpty else { return 0 }

        return expenseTransactions.filter {
            $0.details.uppercased().contains(normalizedPattern)
        }.count
    }

    private func deleteRules(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(rules[index])
        }
        try? modelContext.save()
    }
    
    
    private func currentCategorySummary(for rule: CategoryRule) -> String {
        let matched = matchedExpenseTransactions(for: rule)

        guard !matched.isEmpty else {
            return "Сейчас: нет совпадений"
        }

        let grouped = Dictionary(grouping: matched) { transaction in
            transaction.categoryName ?? "Без категории"
        }

        let sorted = grouped
            .map { (category: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.category < rhs.category
            }

        let preview = sorted
            .prefix(3)
            .map { "\($0.category) (\($0.count))" }
            .joined(separator: ", ")

        return "Сейчас: \(preview)"
    }

    private func matchedExpenseTransactions(for rule: CategoryRule) -> [Transaction] {
        guard rule.isEnabled else { return [] }

        let normalizedPattern = rule.pattern
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalizedPattern.isEmpty else { return [] }

        return expenseTransactions.filter {
            $0.details.uppercased().contains(normalizedPattern)
        }
    }
}
