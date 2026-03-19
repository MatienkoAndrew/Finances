//
//  RulesView.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import SwiftUI
import SwiftData

struct RulesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CategoryRule.priority, order: .reverse)
    private var rules: [CategoryRule]

    @State private var isShowingAddRule = false

    var body: some View {
        NavigationStack {
            Group {
                if rules.isEmpty {
                    ContentUnavailableView(
                        "Нет правил",
                        systemImage: "wand.and.stars",
                        description: Text("Добавь первое правило для автоматической категоризации.")
                    )
                } else {
                    List {
                        ForEach(rules) { rule in
                            NavigationLink {
                                RuleDetailView(rule: rule)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(rule.pattern)
                                            .font(.headline)

                                        Text(rule.category.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)

                                        HStack(spacing: 8) {
                                            Text("Приоритет: \(rule.priority)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            Text(rule.isEnabled ? "Активно" : "Выключено")
                                                .font(.caption)
                                                .foregroundStyle(rule.isEnabled ? .green : .secondary)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    rule.isEnabled.toggle()
                                } label: {
                                    Label(
                                        rule.isEnabled ? "Выключить" : "Включить",
                                        systemImage: rule.isEnabled ? "pause.circle" : "play.circle"
                                    )
                                }
                                .tint(rule.isEnabled ? .orange : .green)
                            }
                        }
                        .onDelete(perform: deleteRules)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Правила")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddRule = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddRule) {
                AddRuleView()
            }
        }
    }

    private func deleteRules(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(rules[index])
        }
    }
}
