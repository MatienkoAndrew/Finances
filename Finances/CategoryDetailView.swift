import SwiftUI
import SwiftData

struct CategoryDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var category: ExpenseCategoryItem

    @Query
    private var expenses: [Expense]

    @Query
    private var rules: [CategoryRule]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @State private var editedName: String = ""
    @State private var originalName: String = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Название") {
                TextField("Название категории", text: $editedName)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Тип") {
                Text(category.isSystem ? "Системная" : "Пользовательская")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Категория")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Сохранить") {
                    saveChanges()
                }
                .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            editedName = category.name
            originalName = category.name
        }
    }

    private func saveChanges() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let oldName = originalName
        let newName = trimmed

        let normalizedNewName = CategoryNameNormalizer.normalize(newName)
        let normalizedOldName = CategoryNameNormalizer.normalize(oldName)

        let duplicateExists = categories.contains { item in
            guard item.persistentModelID != category.persistentModelID else { return false }
            return CategoryNameNormalizer.normalize(item.name) == normalizedNewName
        }

        if duplicateExists {
            errorMessage = "Категория с таким названием уже существует."
            return
        }

        errorMessage = nil

        if normalizedOldName != normalizedNewName {
            for expense in expenses where expense.categoryName == oldName {
                expense.categoryName = newName
            }

            for rule in rules where rule.categoryName == oldName {
                rule.categoryName = newName
            }
        }

        category.name = newName
        originalName = newName
    }
}
