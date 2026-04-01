import SwiftUI
import SwiftData

struct RuleDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var rule: CategoryRule

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @State private var pattern: String = ""
    @State private var selectedCategoryName: String = "Другое"
    @State private var selectedPriority: PriorityLevel = .medium
    @State private var isEnabled: Bool = true
    @State private var isShowingDeleteDialog = false

    private var matchingTransactions: [Transaction] {
        let normalizedPattern = pattern
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalizedPattern.isEmpty else { return [] }

        return transactions.filter {
            $0.kind == .expense &&
            $0.details.uppercased().contains(normalizedPattern)
        }
    }

    var body: some View {
        Form {
            Section("Условие") {
                TextField("Например: CHATGPT", text: $pattern)
                    .textInputAutocapitalization(.characters)
                    .onChange(of: pattern) { _, newValue in
                        rule.pattern = newValue
                        try? modelContext.save()
                    }
            }

            Section("Категория, которую назначит правило") {
                Picker("Категория", selection: $selectedCategoryName) {
                    ForEach(categories) { category in
                        Text(category.name).tag(category.name)
                    }
                }
                .onChange(of: selectedCategoryName) { _, newValue in
                    rule.categoryName = newValue
                    try? modelContext.save()
                }
            }

            Section("Настройки") {
                Picker("Приоритет", selection: $selectedPriority) {
                    ForEach(PriorityLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedPriority) { _, newValue in
                    rule.priority = newValue.rawValue
                    try? modelContext.save()
                }

                Toggle("Правило активно", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        rule.isEnabled = newValue
                        try? modelContext.save()
                    }
            }

            Section("Совпадения в транзакциях") {
                if matchingTransactions.isEmpty {
                    Text("Нет совпадающих расходных транзакций")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Найдено: \(matchingTransactions.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(matchingTransactions.prefix(8)) { transaction in
                        previewRow(transaction: transaction)
                    }

                    if matchingTransactions.count > 8 {
                        Text("Показаны первые 8 совпадений")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    isShowingDeleteDialog = true
                } label: {
                    Label("Удалить правило", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Правило")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Удалить правило?",
            isPresented: $isShowingDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("Удалить правило", role: .destructive) {
                deleteRule()
            }

            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Это правило будет удалено без возможности восстановления.")
        }
        .onAppear {
            pattern = rule.pattern
            selectedCategoryName = rule.categoryName
            selectedPriority = PriorityLevel.from(rule.priority)
            isEnabled = rule.isEnabled
        }
    }

    @ViewBuilder
    private func previewRow(transaction: Transaction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.details)
                    .font(.subheadline)

                HStack(spacing: 8) {
                    Text(transaction.date, format: .dateTime.day().month().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Сейчас: \(transaction.categoryName ?? "Без категории")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(transaction.categoryName ?? "Без категории")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(Capsule())

                if rule.isEnabled {
                    Text("→ \(selectedCategoryName)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func deleteRule() {
        modelContext.delete(rule)
        try? modelContext.save()
        dismiss()
    }
}
