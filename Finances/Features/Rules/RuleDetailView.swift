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
    @State private var showAllMatches = false

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

    private var selectedCategoryItem: ExpenseCategoryItem? {
        CategoryLookup.findCategory(named: selectedCategoryName, in: categories)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    conditionCard
                    categoryRow
                    priorityCard
                    previewCard
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Правило")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isShowingDeleteDialog = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog(
            "Удалить правило?",
            isPresented: $isShowingDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                deleteRule()
            }
            Button("Отмена", role: .cancel) { }
        }
        .onAppear {
            pattern = rule.pattern
            selectedCategoryName = rule.categoryName
            selectedPriority = PriorityLevel.from(rule.priority)
            isEnabled = rule.isEnabled
        }
    }

    // MARK: - UI

    private var conditionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Условие", text: $pattern)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.headline)
                .onChange(of: pattern) { _, newValue in
                    rule.pattern = newValue
                    try? modelContext.save()
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var categoryRow: some View {
        HStack {
            Text("Категория")
                .font(.subheadline)
                .foregroundStyle(.secondary)

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
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                    }

                    Text(selectedCategoryName)
                        .font(.subheadline.weight(.medium))

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
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
        .onChange(of: selectedCategoryName) { _, newValue in
            rule.categoryName = newValue
            try? modelContext.save()
        }
    }

    private var priorityCard: some View {
        VStack(spacing: 10) {
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

            Toggle("Активно", isOn: $isEnabled)
                .onChange(of: isEnabled) { _, newValue in
                    rule.isEnabled = newValue
                    try? modelContext.save()
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
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

            if matchingTransactions.isEmpty {
                Text("Нет совпадений")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let displayed = showAllMatches
                    ? matchingTransactions
                    : Array(matchingTransactions.prefix(8))

                VStack(spacing: 8) {
                    ForEach(displayed) { transaction in
                        previewRow(transaction: transaction)
                    }
                }

                // 👇 ОДНА кнопка
                if matchingTransactions.count > 8 {
                    Button {
                        withAnimation(.easeInOut) {
                            showAllMatches.toggle()
                        }
                    } label: {
                        Text(showAllMatches
                             ? "Свернуть"
                             : "Показать все (\(matchingTransactions.count))")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
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

    // MARK: - Actions

    private func deleteRule() {
        modelContext.delete(rule)
        try? modelContext.save()
        dismiss()
    }
}
