//
//  CategoryDetailView.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import SwiftUI
import SwiftData

struct CategoryDetailView: View {
    @Bindable var category: ExpenseCategoryItem

    @State private var editedName: String = ""

    var body: some View {
        Form {
            Section("Название") {
                TextField("Название категории", text: $editedName)
                    .onChange(of: editedName) { _, newValue in
                        category.name = newValue
                    }
            }

            Section("Тип") {
                Text(category.isSystem ? "Системная" : "Пользовательская")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Категория")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            editedName = category.name
        }
    }
}