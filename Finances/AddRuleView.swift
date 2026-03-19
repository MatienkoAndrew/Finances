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

    @State private var pattern: String = ""
    @State private var selectedCategory: ExpenseCategory = .other
    @State private var priorityText: String = "0"
    @State private var isEnabled: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Условие") {
                    TextField("Например: CHATGPT", text: $pattern)
                        .textInputAutocapitalization(.characters)
                }

                Section("Категория") {
                    Picker("Категория", selection: $selectedCategory) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { category in
                            Text(category.title).tag(category)
                        }
                    }
                }

                Section("Приоритет") {
                    TextField("Приоритет", text: $priorityText)
                        .keyboardType(.numberPad)

                    Toggle("Правило активно", isOn: $isEnabled)
                }
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
        let priority = Int(priorityText) ?? 0

        let rule = CategoryRule(
            pattern: trimmedPattern,
            category: selectedCategory,
            priority: priority,
            isEnabled: isEnabled
        )

        modelContext.insert(rule)
        dismiss()
    }
}