//
//  RuleDetailView.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import SwiftUI
import SwiftData

struct RuleDetailView: View {
    @Bindable var rule: CategoryRule

    @State private var pattern: String = ""
    @State private var selectedCategory: ExpenseCategory = .other
    @State private var priorityText: String = "0"
    @State private var isEnabled: Bool = true

    var body: some View {
        Form {
            Section("Условие") {
                TextField("Например: CHATGPT", text: $pattern)
                    .textInputAutocapitalization(.characters)
                    .onChange(of: pattern) { _, newValue in
                        rule.pattern = newValue
                    }
            }

            Section("Категория") {
                Picker("Категория", selection: $selectedCategory) {
                    ForEach(ExpenseCategory.allCases, id: \.self) { category in
                        Text(category.title).tag(category)
                    }
                }
                .onChange(of: selectedCategory) { _, newValue in
                    rule.category = newValue
                }
            }

            Section("Приоритет") {
                TextField("Приоритет", text: $priorityText)
                    .keyboardType(.numberPad)
                    .onChange(of: priorityText) { _, newValue in
                        rule.priority = Int(newValue) ?? 0
                    }

                Toggle("Правило активно", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        rule.isEnabled = newValue
                    }
            }

            Section("Предпросмотр") {
                previewRow(text: "OPENAI CHATGPT SUBSCR")
                previewRow(text: "GRAB A 9XAWNNRGW2QUAV")
                previewRow(text: "PAYOO MCDONALDS 0053A")
                previewRow(text: "VNPAY XLIII COFFEE")
            }
        }
        .navigationTitle("Правило")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pattern = rule.pattern
            selectedCategory = rule.category
            priorityText = String(rule.priority)
            isEnabled = rule.isEnabled
        }
    }

    @ViewBuilder
    private func previewRow(text: String) -> some View {
        let matches = text.uppercased().contains(pattern.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.subheadline)

                Text(matches ? "Совпадает" : "Не совпадает")
                    .font(.caption)
                    .foregroundStyle(matches ? .green : .secondary)
            }

            Spacer()

            if matches {
                Text(selectedCategory.title)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}