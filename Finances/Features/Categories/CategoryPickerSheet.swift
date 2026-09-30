//
//  CategoryPickerSheet.swift
//  Finances
//
//  Выбор категории в стиле Alipay: сетка категорий, а у категорий с
//  подкатегориями (бейдж «…») по тапу раскрывается панель подкатегорий.
//

import SwiftUI

struct CategoryPickerSheet: View {
    let categories: [ExpenseCategoryItem]
    let initialCategory: String?
    let initialSubcategory: String?
    let onSelect: (_ category: String?, _ subcategory: String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: String?
    @State private var selectedSubcategory: String?
    @State private var expandedCategory: String?
    @State private var isShowingAddCategory = false

    private let columnsPerRow = 5

    init(
        categories: [ExpenseCategoryItem],
        initialCategory: String?,
        initialSubcategory: String?,
        onSelect: @escaping (_ category: String?, _ subcategory: String?) -> Void
    ) {
        self.categories = categories
        self.initialCategory = initialCategory
        self.initialSubcategory = initialSubcategory
        self.onSelect = onSelect

        _selectedCategory = State(initialValue: initialCategory)
        _selectedSubcategory = State(initialValue: initialSubcategory)
        _expandedCategory = State(
            initialValue: DefaultSubcategoryDefinitions.hasSubcategories(initialCategory) ? initialCategory : nil
        )
    }

    private var rows: [[ExpenseCategoryItem]] {
        stride(from: 0, to: categories.count, by: columnsPerRow).map { start in
            Array(categories[start..<min(start + columnsPerRow, categories.count)])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(rows.indices, id: \.self) { rowIndex in
                        let row = rows[rowIndex]

                        HStack(alignment: .top, spacing: 8) {
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
                           row.contains(where: { $0.name == expandedCategory }),
                           let subs = DefaultSubcategoryDefinitions.subcategories(for: expandedCategory) {
                            subcategoryPanel(subs)
                        }
                    }

                    Button {
                        isShowingAddCategory = true
                    } label: {
                        Label("Новая категория", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("Выбор категории")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isShowingAddCategory) {
                AddCategorySheet { newCategoryName in
                    selectedCategory = newCategoryName
                    selectedSubcategory = nil
                    expandedCategory = DefaultSubcategoryDefinitions.hasSubcategories(newCategoryName) ? newCategoryName : nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { commit() }
                        .fontWeight(.semibold)
                        .disabled(selectedCategory == nil)
                }
            }
        }
    }

    // MARK: - Cells

    private func categoryCell(_ category: ExpenseCategoryItem) -> some View {
        let isSelected = selectedCategory == category.name
        let hasSubs = DefaultSubcategoryDefinitions.hasSubcategories(category.name)

        return Button {
            handleCategoryTap(category)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(Color(hex: category.colorHex) ?? .gray)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: category.iconName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                    if hasSubs {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                            .offset(x: 5, y: -3)
                    }
                }

                Text(category.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func subcategoryPanel(_ subs: [DefaultSubcategoryDefinition]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(subs) { sub in
                let isSelected = selectedSubcategory == sub.name

                Button {
                    selectedSubcategory = sub.name
                } label: {
                    VStack(spacing: 6) {
                        Text(sub.emoji)
                            .font(.system(size: 24))

                        Text(sub.name)
                            .font(.caption)
                            .foregroundStyle(isSelected ? Color.accentColor : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isSelected ? Color.accentColor.opacity(0.14) : Color.gray.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }

    // MARK: - Actions

    private func handleCategoryTap(_ category: ExpenseCategoryItem) {
        selectedCategory = category.name

        if DefaultSubcategoryDefinitions.hasSubcategories(category.name) {
            withAnimation(.smooth(duration: 0.22)) {
                expandedCategory = category.name
            }
            // По умолчанию выбираем «Другое», если ещё ничего валидного не выбрано.
            let validSubs = DefaultSubcategoryDefinitions.subcategories(for: category.name)?.map(\.name) ?? []
            if selectedSubcategory == nil || !validSubs.contains(selectedSubcategory!) {
                selectedSubcategory = DefaultSubcategoryDefinitions.defaultSubcategory(for: category.name)
            }
        } else {
            withAnimation(.smooth(duration: 0.22)) {
                expandedCategory = nil
            }
            selectedSubcategory = nil
        }
    }

    private func commit() {
        onSelect(selectedCategory, selectedSubcategory)
        dismiss()
    }
}
