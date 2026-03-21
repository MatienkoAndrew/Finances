//
//  CategoriesView.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @State private var isShowingAddCategory = false

    var body: some View {
        List {
            ForEach(categories) { category in
                NavigationLink {
                    CategoryDetailView(category: category)
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: category.colorHex) ?? .gray)
                            .frame(width: 28, height: 28)
                            .overlay {
                                Image(systemName: category.iconName)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
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
            }
            .onDelete(perform: deleteCategories)
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
    }

    private func deleteCategories(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(categories[index])
        }
    }
}
