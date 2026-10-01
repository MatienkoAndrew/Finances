import SwiftUI
import SwiftData

/// Категории сеткой, как в выборе категории. Тап — редактор, долгое нажатие —
/// режим правки: категории покачиваются, их можно перетаскивать и удалять.
struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var categories: [ExpenseCategoryItem]

    @State private var isEditing = false
    @State private var editorTarget: EditorTarget?

    @State private var categoryToDelete: ExpenseCategoryItem?
    @State private var isShowingDeleteOptions = false
    @State private var isShowingReassignSheet = false

    private enum EditorTarget: Identifiable {
        case new
        case edit(ExpenseCategoryItem)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let category): return "\(category.persistentModelID.hashValue)"
            }
        }
    }

    private var ordered: [ExpenseCategoryItem] {
        ExpenseCategoryItem.ordered(categories)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Group {
                    if isEditing {
                        ReorderableCategoryGrid(categories: ordered) { category in
                            requestDelete(category)
                        }
                    } else {
                        grid
                    }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text(isEditing
                     ? "Перетаскивай категории, чтобы поменять порядок, «−» — удалить."
                     : "Нажми на категорию, чтобы изменить её и подкатегории. Удерживай — чтобы переставить.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Категории")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button("Готово") {
                        withAnimation(.snappy(duration: 0.25)) { isEditing = false }
                    }
                    .fontWeight(.semibold)
                } else {
                    Button {
                        editorTarget = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Новая категория")
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: isEditing) { _, newValue in newValue }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new:
                CategoryEditorSheet(category: nil)
            case .edit(let category):
                CategoryEditorSheet(category: category, onDelete: requestDelete)
            }
        }
        .confirmationDialog(
            "Удалить категорию «\(categoryToDelete?.name ?? "")»?",
            isPresented: $isShowingDeleteOptions,
            titleVisibility: .visible
        ) {
            Button("Перенести операции в другую категорию") {
                isShowingReassignSheet = true
            }

            Button("Удалить, операции оставить без категории", role: .destructive) {
                deleteCategory(movingTo: nil)
            }

            Button("Отмена", role: .cancel) {
                categoryToDelete = nil
            }
        }
        .sheet(isPresented: $isShowingReassignSheet) {
            if let categoryToDelete {
                ReassignCategoryView(
                    categoryToDelete: categoryToDelete,
                    categories: ordered.filter { $0.persistentModelID != categoryToDelete.persistentModelID },
                    onConfirm: { newCategoryName in
                        deleteCategory(movingTo: newCategoryName)
                    }
                )
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 14) {
            ForEach(ordered) { category in
                CategoryGridCell(category: category)
                    .onTapGesture {
                        editorTarget = .edit(category)
                    }
                    .onLongPressGesture(minimumDuration: 0.35) {
                        withAnimation(.snappy(duration: 0.25)) { isEditing = true }
                    }
            }

            Button {
                editorTarget = .new
            } label: {
                VStack(spacing: 7) {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(.tertiary)
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(4)

                    Text("Новая")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Delete

    private func requestDelete(_ category: ExpenseCategoryItem) {
        categoryToDelete = category
        isShowingDeleteOptions = true
    }

    /// Удаляет категорию и её подкатегории; операции и правила переносит в `newCategoryName`
    /// (подкатегория сбрасывается — у другой категории она своя) или оставляет без категории.
    private func deleteCategory(movingTo newCategoryName: String?) {
        guard let category = categoryToDelete else { return }
        let name = category.name

        let transactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
        let expenses = (try? modelContext.fetch(FetchDescriptor<Expense>())) ?? []
        let rules = (try? modelContext.fetch(FetchDescriptor<CategoryRule>())) ?? []

        for transaction in transactions where transaction.categoryName == name {
            transaction.subcategoryName = nil
        }
        for rule in rules where rule.categoryName == name {
            rule.subcategoryName = nil
        }

        if let newCategoryName {
            TransactionCategorySync.reassignCategoryReferences(
                from: name,
                to: newCategoryName,
                transactions: transactions,
                legacyExpenses: expenses,
                rules: rules
            )
        } else {
            TransactionCategorySync.clearCategoryReferences(
                named: name,
                transactions: transactions,
                legacyExpenses: expenses,
                rules: rules
            )
        }

        let subcategories = (try? modelContext.fetch(FetchDescriptor<ExpenseSubcategoryItem>())) ?? []
        for item in subcategories where CategoryNameNormalizer.normalize(item.categoryName) == CategoryNameNormalizer.normalize(name) {
            modelContext.delete(item)
        }

        modelContext.delete(category)
        try? modelContext.save()
        SubcategoryRegistry.shared.reload(context: modelContext)
        categoryToDelete = nil
    }
}
