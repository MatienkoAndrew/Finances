//
//  AddCategoryView.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import SwiftUI
import SwiftData

struct AddCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например: Отель", text: $name)
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
        let category = ExpenseCategoryItem(name: trimmed, isSystem: false)
        modelContext.insert(category)
        dismiss()
    }
}