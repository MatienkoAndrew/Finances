import SwiftUI
import SwiftData

struct RuleDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var rule: CategoryRule

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @State private var pattern: String = ""
    @State private var selectedCategoryName: String = "Другое"
    @State private var priorityText: String = "0"
    @State private var isEnabled: Bool = true

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

            Section("Категория") {
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

            Section("Приоритет") {
                TextField("Приоритет", text: $priorityText)
                    .keyboardType(.numberPad)
                    .onChange(of: priorityText) { _, newValue in
                        rule.priority = Int(newValue) ?? 0
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
                }
            }
        }
        .navigationTitle("Правило")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pattern = rule.pattern
            selectedCategoryName = rule.categoryName
            priorityText = String(rule.priority)
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

                    if let currentCategory = transaction.categoryName {
                        Text("Сейчас: \(currentCategory)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text(selectedCategoryName)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
        }
    }
}
