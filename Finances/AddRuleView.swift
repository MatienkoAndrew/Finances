//
//  AddRuleView.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import SwiftUI
import SwiftData

struct AddRuleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @State private var pattern: String = ""
    @State private var selectedCategoryName: String = "Другое"
    @State private var selectedPriority: PriorityLevel = .medium
    @State private var isEnabled: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Условие") {
                    TextField("Например: CHATGPT", text: $pattern)
                        .textInputAutocapitalization(.characters)
                }

                Section("Категория") {
                    Picker("Категория", selection: $selectedCategoryName) {
                        ForEach(categories) { category in
                            Text(category.name).tag(category.name)
                        }
                    }
                }

                Picker("Приоритет", selection: $selectedPriority) {
                    ForEach(PriorityLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle("Новое правило")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        saveRule()
                    }
                    .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveRule() {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)

        let rule = CategoryRule(
            pattern: trimmedPattern,
            categoryName: selectedCategoryName,
            priority: selectedPriority.rawValue,
            isEnabled: isEnabled
        )

        modelContext.insert(rule)
        dismiss()
    }
}
