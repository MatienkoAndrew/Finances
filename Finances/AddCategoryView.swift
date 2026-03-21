import SwiftUI
import SwiftData

struct AddCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @State private var name: String = ""
    @State private var selectedIconName: String = "square.grid.2x2.fill"
    @State private var selectedColorHex: String = "#8E8E93"
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например: Отель", text: $name)
                }

                Section("Внешний вид") {
                    iconGrid
                    colorGrid
                }

                previewSection

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

    private var iconGrid: some View {
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

    private var colorGrid: some View {
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

    private var previewSection: some View {
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

                Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Название категории" : name)
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

        let category = ExpenseCategoryItem(
            name: trimmed,
            iconName: selectedIconName,
            colorHex: selectedColorHex,
            isSystem: false
        )

        modelContext.insert(category)
        dismiss()
    }
}
