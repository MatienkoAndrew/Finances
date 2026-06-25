import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @Query
    private var expenses: [Expense]

    @Query
    private var rules: [CategoryRule]

    @State private var isShowingAddCategory = false

    @State private var categoryToDelete: ExpenseCategoryItem?
    @State private var isShowingDeleteOptions = false
    @State private var isShowingReassignSheet = false

    var body: some View {
        List {
            ForEach(categories) { category in
                categoryRow(category)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Категории")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAddCategory = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddCategory) {
            AddCategoryView()
        }
        .confirmationDialog(
            "Удалить категорию?",
            isPresented: $isShowingDeleteOptions,
            titleVisibility: .visible
        ) {
            Button("Удалить и очистить категорию", role: .destructive) {
                deleteCategoryAndClearReferences()
            }

            Button("Перенести в другую категорию") {
                isShowingReassignSheet = true
            }

            Button("Отмена", role: .cancel) {}
        } message: {
            if let categoryToDelete {
                Text("Категория \"\(categoryToDelete.name)\" используется в транзакциях и правилах.")
            }
        }
        .sheet(isPresented: $isShowingReassignSheet) {
            if let categoryToDelete {
                ReassignCategoryView(
                    categoryToDelete: categoryToDelete,
                    categories: categories.filter { $0.name != categoryToDelete.name },
                    onConfirm: { newCategoryName in
                        reassignAndDeleteCategory(newCategoryName: newCategoryName)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: ExpenseCategoryItem) -> some View {
        NavigationLink {
            CategoryDetailView(category: category)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: category.colorHex) ?? .gray)
                    .frame(width: 28, height: 28)
                    .overlay {
                        CategoryIconView(category: category, size: 30)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name)
                        .font(.headline)

                    Text(category.isSystem ? "Системная" : "Пользовательская")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                categoryToDelete = category
                isShowingDeleteOptions = true
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    private func deleteCategoryAndClearReferences() {
        guard let categoryToDelete else { return }

        TransactionCategorySync.clearCategoryReferences(
            named: categoryToDelete.name,
            transactions: transactions,
            legacyExpenses: expenses,
            rules: rules
        )

        modelContext.delete(categoryToDelete)
        try? modelContext.save()
        self.categoryToDelete = nil
    }

    private func reassignAndDeleteCategory(newCategoryName: String) {
        guard let categoryToDelete else { return }

        TransactionCategorySync.reassignCategoryReferences(
            from: categoryToDelete.name,
            to: newCategoryName,
            transactions: transactions,
            legacyExpenses: expenses,
            rules: rules
        )

        modelContext.delete(categoryToDelete)
        try? modelContext.save()
        self.categoryToDelete = nil
    }
}
