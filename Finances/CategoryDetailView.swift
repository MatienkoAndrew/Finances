import SwiftUI
import SwiftData

struct CategoryDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var category: ExpenseCategoryItem

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @Query
    private var expenses: [Expense]

    @Query
    private var rules: [CategoryRule]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @State private var editedName: String = ""
    @State private var originalName: String = ""
    @State private var selectedIconName: String = "square.grid.2x2.fill"
    @State private var selectedColorHex: String = "#8E8E93"
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Название") {
                TextField("Название категории", text: $editedName)
            }

            Section("Иконка") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(CategoryAppearance.iconOptions, id: \.self) { icon in
                        Button {
                            selectedIconName = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    selectedIconName == icon
                                    ? Color.primary.opacity(0.12)
                                    : Color.gray.opacity(0.08)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Цвет") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(CategoryAppearance.colorOptions, id: \.self) { hex in
                        Button {
                            selectedColorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex) ?? .gray)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if selectedColorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Предпросмотр") {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: selectedColorHex) ?? .gray)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: selectedIconName)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }

                    Text(editedName.isEmpty ? "Название категории" : editedName)
                }
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
            selectedIconName = category.iconName
            selectedColorHex = category.colorHex
        }
    }

    private func saveChanges() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let oldName = originalName
        let newName = trimmed
        let normalizedNewName = CategoryNameNormalizer.normalize(newName)

        let duplicateExists = categories.contains { item in
            guard item.persistentModelID != category.persistentModelID else { return false }
            return CategoryNameNormalizer.normalize(item.name) == normalizedNewName
        }

        if duplicateExists {
            errorMessage = "Категория с таким названием уже существует."
            return
        }

        errorMessage = nil

        if oldName != newName {
            TransactionCategorySync.renameCategory(
                from: oldName,
                to: newName,
                transactions: transactions,
                legacyExpenses: expenses,
                rules: rules
            )
        }

        category.name = newName
        category.iconName = selectedIconName
        category.colorHex = selectedColorHex
        originalName = newName

        try? modelContext.save()
    }
}
