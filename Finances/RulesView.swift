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
    @State private var isShowingApplyConfirmation = false

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
                                isShowingApplyConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "wand.and.stars")
                                    Text("Применить правила к транзакциям")
                                    Spacer()
                                }
                            }

                            Text("Будут категоризированы расходные транзакции без категории.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(rules) { rule in
                            NavigationLink {
                                RuleDetailView(rule: rule)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(rule.pattern)
                                            .font(.headline)

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

                                        HStack(spacing: 8) {
                                            Text("Приоритет: \(rule.priority)")
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
            .alert("Применить правила?", isPresented: $isShowingApplyConfirmation) {
                Button("Применить") {
                    applyRulesToTransactions()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Будут обновлены только расходные транзакции без категории.")
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

    private func applyRulesToTransactions() {
        TransactionCategorySync.autoCategorizeTransactions(
            transactions,
            rules: rules,
            overwriteExisting: false
        )

        try? modelContext.save()
    }

    private func deleteRules(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(rules[index])
        }
        try? modelContext.save()
    }
}
