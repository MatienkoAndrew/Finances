//
//  CategoryPickerSheet.swift
//  Finances
//
//  Выбор категории в стиле Alipay: сетка цветных категорий, у категорий с
//  подкатегориями по тапу раскрывается панель подкатегорий. Выбор — в одно касание:
//  категория без подкатегорий или подкатегория сразу применяются. Долгое нажатие —
//  режим правки порядка, как на домашнем экране.
//

import SwiftUI

struct CategoryPickerSheet: View {
    let categories: [ExpenseCategoryItem]
    let initialCategory: String?
    let initialSubcategory: String?
    /// Подзаголовок — обычно название операции.
    let subtitle: String?
    let onSelect: (_ category: String?, _ subcategory: String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var expandedCategory: String?
    @State private var isShowingAddCategory = false
    @State private var isReordering = false
    @State private var selectionFeedback = 0

    private let columnsPerRow = 4

    init(
        categories: [ExpenseCategoryItem],
        initialCategory: String?,
        initialSubcategory: String?,
        subtitle: String? = nil,
        onSelect: @escaping (_ category: String?, _ subcategory: String?) -> Void
    ) {
        self.categories = categories
        self.initialCategory = initialCategory
        self.initialSubcategory = initialSubcategory
        self.subtitle = subtitle
        self.onSelect = onSelect

        _expandedCategory = State(
            initialValue: DefaultSubcategoryDefinitions.hasSubcategories(initialCategory) ? initialCategory : nil
        )
    }

    private var ordered: [ExpenseCategoryItem] {
        ExpenseCategoryItem.ordered(categories)
    }

    private var rows: [[ExpenseCategoryItem]] {
        let ordered = ordered
        return stride(from: 0, to: ordered.count, by: columnsPerRow).map { start in
            Array(ordered[start..<min(start + columnsPerRow, ordered.count)])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isReordering {
                    VStack(spacing: 12) {
                        ReorderableCategoryGrid(categories: ordered, columns: columnsPerRow)
                        Text("Перетаскивай категории, чтобы поменять порядок")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                } else {
                VStack(spacing: 14) {
                    ForEach(rows.indices, id: \.self) { rowIndex in
                        let row = rows[rowIndex]

                        HStack(alignment: .top, spacing: 6) {
                            ForEach(row) { category in
                                categoryCell(category)
                            }

                            // Добиваем последний ряд пустыми ячейками для выравнивания.
                            if row.count < columnsPerRow {
                                ForEach(0..<(columnsPerRow - row.count), id: \.self) { _ in
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }

                        if let expandedCategory,
                           let category = row.first(where: { $0.name == expandedCategory }),
                           let subs = DefaultSubcategoryDefinitions.subcategories(for: expandedCategory) {
                            subcategoryPanel(subs, in: category)
                        }
                    }

                    Button {
                        isShowingAddCategory = true
                    } label: {
                        Label("Новая категория", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                                    .foregroundStyle(.tertiary)
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                }
                .padding(.horizontal)
                .padding(.bottom)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Категория")
                            .font(.headline)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isReordering {
                        Button("Готово") {
                            withAnimation(.snappy(duration: 0.25)) { isReordering = false }
                        }
                        .fontWeight(.semibold)
                    } else {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color.gray.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Закрыть")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddCategory) {
                CategoryEditorSheet(category: nil) { newCategoryName in
                    if DefaultSubcategoryDefinitions.hasSubcategories(newCategoryName) {
                        expandedCategory = newCategoryName
                    } else {
                        select(newCategoryName, nil)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .sensoryFeedback(.impact(weight: .medium), trigger: isReordering) { _, newValue in newValue }
    }

    // MARK: - Cells

    private func categoryCell(_ category: ExpenseCategoryItem) -> some View {
        let isCurrent = CategoryNameNormalizer.normalize(initialCategory ?? "") == CategoryNameNormalizer.normalize(category.name)

        return CategoryGridCell(
            category: category,
            isHighlighted: isCurrent,
            isExpanded: expandedCategory == category.name,
            showsCheckmark: isCurrent
        )
        .onTapGesture {
            handleCategoryTap(category)
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            withAnimation(.snappy(duration: 0.25)) {
                expandedCategory = nil
                isReordering = true
            }
        }
        .accessibilityAddTraits(.isButton)
    }

    private func subcategoryPanel(_ subs: [DefaultSubcategoryDefinition], in category: ExpenseCategoryItem) -> some View {
        let color = Color(hex: category.colorHex) ?? .gray
        let isCurrentCategory = CategoryNameNormalizer.normalize(initialCategory ?? "") == CategoryNameNormalizer.normalize(category.name)

        return VStack(alignment: .leading, spacing: 10) {
            Text(category.name.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .padding(.leading, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(subs) { sub in
                    let isSelected = isCurrentCategory && initialSubcategory == sub.name

                    Button {
                        select(category.name, sub.name)
                    } label: {
                        HStack(spacing: 6) {
                            Text(sub.emoji)
                                .font(.system(size: 17))
                            Text(sub.name)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .background(
                            isSelected ? AnyShapeStyle(color) : AnyShapeStyle(Color(.systemBackground)),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
    }

    // MARK: - Actions

    private func handleCategoryTap(_ category: ExpenseCategoryItem) {
        if DefaultSubcategoryDefinitions.hasSubcategories(category.name) {
            selectionFeedback += 1
            withAnimation(.snappy(duration: 0.25)) {
                expandedCategory = expandedCategory == category.name ? nil : category.name
            }
        } else {
            select(category.name, nil)
        }
    }

    private func select(_ category: String, _ subcategory: String?) {
        selectionFeedback += 1
        onSelect(category, subcategory)
        dismiss()
    }
}

/// Капсула с категорией операции: цвет категории, эмодзи подкатегории
/// (или иконка категории) и «Категория · Подкатегория».
struct CategoryChip: View {
    let category: ExpenseCategoryItem?
    let categoryName: String
    let subcategoryName: String?
    var showsChevron = true

    private var color: Color {
        category.flatMap { Color(hex: $0.colorHex) } ?? .gray
    }

    private var subcategoryEmoji: String? {
        guard let subcategoryName else { return nil }
        return DefaultSubcategoryDefinitions.subcategories(for: categoryName)?
            .first { $0.name == subcategoryName }?.emoji
    }

    var body: some View {
        HStack(spacing: 5) {
            if let subcategoryEmoji {
                Text(subcategoryEmoji)
                    .font(.system(size: 12))
            } else if let category {
                CategoryIconView(category: category, size: 16)
            }

            Text(subcategoryName.map { "\(categoryName) · \($0)" } ?? categoryName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .heavy))
                    .opacity(0.6)
            }
        }
        .foregroundStyle(color)
        .padding(.leading, subcategoryEmoji == nil && category != nil ? 4 : 8)
        .padding(.trailing, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.13), in: Capsule())
    }
}
