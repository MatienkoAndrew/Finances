import SwiftUI
import SwiftData

struct AddCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @State private var name: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например: Отель", text: $name)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Новая категория")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = CategoryNameNormalizer.normalize(trimmed)

        guard !trimmed.isEmpty else { return }

        let alreadyExists = categories.contains {
            CategoryNameNormalizer.normalize($0.name) == normalized
        }

        if alreadyExists {
            errorMessage = "Категория с таким названием уже существует."
            return
        }

        let category = ExpenseCategoryItem(name: trimmed, isSystem: false)
        modelContext.insert(category)
        dismiss()
    }
}
