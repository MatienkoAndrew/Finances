import SwiftUI

struct BuiltInRulesView: View {
    @State private var rules: [BuiltInCategoryRule] = []
    @State private var searchText = ""
    
    private var filteredRules: [BuiltInCategoryRule] {
        if searchText.isEmpty {
            return rules
        }
        return rules.filter { rule in
            rule.description.localizedCaseInsensitiveContains(searchText) ||
            rule.pattern.localizedCaseInsensitiveContains(searchText) ||
            rule.categoryName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var groupedRules: [(category: String, rules: [BuiltInCategoryRule])] {
        let grouped = Dictionary(grouping: filteredRules) { $0.categoryName }
        return grouped.map { (category: $0.key, rules: $0.value) }
            .sorted { $0.category < $1.category }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Встроенные правила")
                                .font(.subheadline.bold())
                            Text("Автоматически определяют категории при импорте. Работают с меньшим приоритетом, чем ваши правила.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    EmptyView()
                }
                
                ForEach(groupedRules, id: \.category) { group in
                    Section {
                        ForEach(group.rules.indices, id: \.self) { index in
                            let rule = group.rules[index]
                            
                            HStack(spacing: 12) {
                                Toggle("", isOn: Binding(
                                    get: { rule.isEnabled },
                                    set: { newValue in
                                        toggleRule(id: rule.id, isEnabled: newValue)
                                    }
                                ))
                                .labelsHidden()
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rule.description)
                                        .font(.body)
                                        .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                                    
                                    Text("Паттерн: \(rule.pattern)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.gray.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                
                                Spacer()
                            }
                            .opacity(rule.isEnabled ? 1.0 : 0.5)
                        }
                    } header: {
                        Text(group.category)
                    }
                }
            }
            .navigationTitle("Встроенные правила")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Поиск правил")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            enableAll()
                        } label: {
                            Label("Включить все", systemImage: "checkmark.circle")
                        }
                        
                        Button {
                            disableAll()
                        } label: {
                            Label("Выключить все", systemImage: "xmark.circle")
                        }
                        
                        Button {
                            resetToDefaults()
                        } label: {
                            Label("Сбросить", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                loadRules()
            }
        }
    }
    
    private func loadRules() {
        let states = BuiltInCategoryRulesManager.loadStates()
        rules = BuiltInCategoryRulesManager.allRules.map { rule in
            var mutableRule = rule
            if let savedState = states[rule.id] {
                mutableRule.isEnabled = savedState
            }
            return mutableRule
        }
    }
    
    private func toggleRule(id: String, isEnabled: Bool) {
        BuiltInCategoryRulesManager.updateRuleState(id: id, isEnabled: isEnabled)
        loadRules()
    }
    
    private func enableAll() {
        for rule in rules {
            BuiltInCategoryRulesManager.updateRuleState(id: rule.id, isEnabled: true)
        }
        loadRules()
    }
    
    private func disableAll() {
        for rule in rules {
            BuiltInCategoryRulesManager.updateRuleState(id: rule.id, isEnabled: false)
        }
        loadRules()
    }
    
    private func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: "builtInCategoryRulesStates")
        loadRules()
    }
}

#Preview {
    BuiltInRulesView()
}
