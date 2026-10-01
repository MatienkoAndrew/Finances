import SwiftUI
import SwiftData
import Foundation

/// Утилита для массового добавления меток к транзакциям
struct BulkTaggingHelper {
    
    /// Применить метку ко всем транзакциям в указанном периоде
    static func applyTag(
        _ tagName: String,
        from startDate: Date,
        to endDate: Date,
        transactions: [Transaction],
        modelContext: ModelContext
    ) -> Int {
        var count = 0
        
        for transaction in transactions {
            if transaction.date >= startDate && transaction.date <= endDate {
                transaction.addTag(tagName)
                count += 1
            }
        }
        
        try? modelContext.save()
        return count
    }
    
    /// Удалить метку со всех транзакций
    static func removeTag(
        _ tagName: String,
        transactions: [Transaction],
        modelContext: ModelContext
    ) -> Int {
        var count = 0
        
        for transaction in transactions {
            if transaction.hasTag(tagName) {
                transaction.removeTag(tagName)
                count += 1
            }
        }
        
        try? modelContext.save()
        return count
    }
    
    /// Получить транзакции с указанной меткой
    static func transactions(
        withTag tagName: String,
        from allTransactions: [Transaction]
    ) -> [Transaction] {
        allTransactions.filter { $0.hasTag(tagName) }
    }
}

/// View для быстрого добавления метки к транзакциям за период
struct QuickTagView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \TransactionTag.createdAt, order: .reverse)
    private var allTags: [TransactionTag]
    
    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    
    @State private var selectedTag: TransactionTag?
    @State private var startDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var endDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var showingCreateTag = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Выберите метку") {
                    if allTags.isEmpty {
                        Button {
                            showingCreateTag = true
                        } label: {
                            Label("Создать метку", systemImage: "plus.circle.fill")
                        }
                    } else {
                        Picker("Метка", selection: $selectedTag) {
                            Text("Выберите метку").tag(nil as TransactionTag?)
                            ForEach(allTags) { tag in
                                HStack {
                                    Text(tag.displayIcon)
                                    Text(tag.name)
                                }
                                .tag(tag as TransactionTag?)
                            }
                        }
                        
                        Button {
                            showingCreateTag = true
                        } label: {
                            Label("Создать новую метку", systemImage: "plus.circle")
                        }
                    }
                }
                
                Section("Период") {
                    DatePicker("С", selection: $startDate, displayedComponents: .date)
                    DatePicker("По", selection: $endDate, displayedComponents: .date)
                }
                
                Section {
                    HStack {
                        Text("Будет помечено транзакций:")
                        Spacer()
                        Text("\(affectedCount)")
                            .foregroundStyle(.secondary)
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("Добавить метку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Применить") {
                        applyTag()
                    }
                    .disabled(selectedTag == nil || affectedCount == 0)
                }
            }
            .sheet(isPresented: $showingCreateTag) {
                CreateTagView()
            }
            .onChange(of: selectedTag) { _, newTag in
                // Автоматически подставляем период метки, если он задан
                if let tag = newTag, let start = tag.startDate, let end = tag.endDate {
                    startDate = start
                    endDate = end
                }
            }
        }
    }
    
    private var affectedCount: Int {
        transactions.filter { transaction in
            transaction.date >= startDate && transaction.date <= endDate
        }.count
    }
    
    private func applyTag() {
        guard let tag = selectedTag else { return }
        
        let count = BulkTaggingHelper.applyTag(
            tag.name,
            from: startDate,
            to: endDate,
            transactions: transactions,
            modelContext: modelContext
        )
        
        print("✅ Добавлено метка '\(tag.name)' к \(count) транзакциям")
        dismiss()
    }
}

#Preview {
    QuickTagView()
        .modelContainer(for: [TransactionTag.self, Transaction.self], inMemory: true)
}
