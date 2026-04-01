import SwiftUI
import SwiftData

struct CategoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
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
    @State private var editedEmoji: String = ""
    @State private var selectedColorHex: String = "#8E8E93"
    @State private var errorMessage: String?
    @State private var isShowingEmojiPicker = false

    @FocusState private var isNameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                topPreviewSection
                quickIconsSection
                colorSection

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                typeSection
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
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
        .sheet(isPresented: $isShowingEmojiPicker) {
            EmojiPickerSheet(selectedEmoji: $editedEmoji)
        }
        .onAppear {
            editedName = category.name
            originalName = category.name
            selectedIconName = category.iconName
            editedEmoji = category.emoji ?? ""
            selectedColorHex = category.colorHex
        }
    }

    private var topPreviewSection: some View {
        VStack(spacing: 18) {
            Button {
                isShowingEmojiPicker = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(hex: selectedColorHex)?.opacity(0.22) ?? Color.gray.opacity(0.18))
                        .frame(width: 156, height: 156)

                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 84, height: 84)
                        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
                        .overlay {
                            previewSymbol
                        }
                }
            }
            .buttonStyle(.plain)

            TextField("Название", text: $editedName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.title2.weight(.medium))
                .focused($isNameFocused)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var quickIconsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Быстрые варианты")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                ForEach(CategoryAppearance.iconOptions, id: \.self) { iconName in
                    Button {
                        selectedIconName = iconName
                        if !editedEmoji.isEmpty {
                            editedEmoji = ""
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .frame(height: 58)
                            .overlay {
                                ZStack {
                                    if selectedIconName == iconName && editedEmoji.isEmpty {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.accentColor, lineWidth: 2)
                                    }

                                    Image(systemName: iconName)
                                        .font(.title2)
                                        .foregroundStyle(.primary)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Цвет фона")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 14) {
                ForEach(CategoryAppearance.colorOptions, id: \.self) { hex in
                    Button {
                        selectedColorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .frame(width: 42, height: 42)
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
        .padding(18)
        .background(cardBackground)
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Тип")
                .font(.headline)

            Text(category.isSystem ? "Системная" : "Пользовательская")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
    }

    @ViewBuilder
    private var previewSymbol: some View {
        if !editedEmoji.isEmpty {
            Text(editedEmoji)
                .font(.system(size: 36))
        } else {
            Image(systemName: selectedIconName)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color(hex: selectedColorHex) ?? .blue)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(.systemBackground))
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
        category.emoji = editedEmoji.isEmpty ? nil : editedEmoji
        category.colorHex = selectedColorHex
        originalName = newName

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Не удалось сохранить изменения."
        }
    }
}
