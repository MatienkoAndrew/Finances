//
//  ReassignCategoryView.swift
//  Finances
//
//  Created by Андрей Матиенко on 21.03.2026.
//


import SwiftUI

struct ReassignCategoryView: View {
    @Environment(\.dismiss) private var dismiss

    let categoryToDelete: ExpenseCategoryItem
    let categories: [ExpenseCategoryItem]
    let onConfirm: (String) -> Void

    @State private var selectedCategoryName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Удаляемая категория") {
                    Text(categoryToDelete.name)
                }

                Section("Перенести в") {
                    if categories.isEmpty {
                        Text("Нет доступных категорий")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Новая категория", selection: $selectedCategoryName) {
                            ForEach(categories) { category in
                                Text(category.name).tag(category.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Перенос категории")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Перенести") {
                        onConfirm(selectedCategoryName)
                        dismiss()
                    }
                    .disabled(selectedCategoryName.isEmpty || categories.isEmpty)
                }
            }
            .onAppear {
                selectedCategoryName = categories.first?.name ?? ""
            }
        }
    }
}