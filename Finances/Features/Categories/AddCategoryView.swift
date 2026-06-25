import SwiftUI
import SwiftData

struct AddCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @State private var name: String = ""
    @State private var selectedIconName: String = CategoryAppearance.iconOptions.first ?? "square.grid.2x2.fill"
    @State private var emoji: String = ""
    @State private var selectedColorHex: String = CategoryAppearance.colorOptions.first ?? "#FF3B30"
    @State private var errorMessage: String?
    @State private var isShowingEmojiPicker = false

    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
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
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
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
            .sheet(isPresented: $isShowingEmojiPicker) {
                EmojiPickerSheet(selectedEmoji: $emoji)
            }
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

            TextField("Название", text: $name)
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
                        if !emoji.isEmpty {
                            emoji = ""
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .frame(height: 58)
                            .overlay {
                                ZStack {
                                    if selectedIconName == iconName && emoji.isEmpty {
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

    @ViewBuilder
    private var previewSymbol: some View {
        if !emoji.isEmpty {
            Text(emoji)
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

        errorMessage = nil

        let category = ExpenseCategoryItem(
            name: trimmed,
            iconName: selectedIconName,
            emoji: emoji.isEmpty ? nil : emoji,
            colorHex: selectedColorHex,
            isSystem: false
        )

        modelContext.insert(category)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Не удалось сохранить категорию."
        }
    }
}
