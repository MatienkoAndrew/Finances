import SwiftUI
import SwiftData

struct TagsManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \TransactionTag.createdAt, order: .reverse)
    private var tags: [TransactionTag]
    
    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    
    @State private var showingCreateSheet = false
    @State private var tagToEdit: TransactionTag?
    
    var body: some View {
        NavigationStack {
            List {
                if tags.isEmpty {
                    ContentUnavailableView(
                        "Нет меток",
                        systemImage: "tag.slash",
                        description: Text("Создайте метку для группировки транзакций по странам, проектам или событиям")
                    )
                } else {
                    ForEach(tags) { tag in
                        TagRowView(tag: tag, transactionCount: transactionCount(for: tag))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                tagToEdit = tag
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteTag(tag)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .navigationTitle("Метки")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateTagView()
            }
            .sheet(item: $tagToEdit) { tag in
                EditTagView(tag: tag)
            }
        }
    }
    
    private func transactionCount(for tag: TransactionTag) -> Int {
        transactions.filter { $0.tagNames?.contains(tag.name) == true }.count
    }
    
    private func deleteTag(_ tag: TransactionTag) {
        // Удаляем метку из всех транзакций
        for transaction in transactions where transaction.hasTag(tag.name) {
            transaction.removeTag(tag.name)
        }
        
        // Удаляем саму метку
        modelContext.delete(tag)
    }
}

// MARK: - Tag Row

struct TagRowView: View {
    let tag: TransactionTag
    let transactionCount: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Иконка
            Text(tag.displayIcon)
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color(hex: tag.colorHex ?? "#007AFF").opacity(0.15))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(tag.name)
                    .font(.headline)
                
                if tag.startDate != nil || tag.endDate != nil {
                    Text(tag.periodDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text("\(transactionCount) транзакций")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create Tag View

struct CreateTagView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    
    @State private var name: String = ""
    @State private var icon: String = "🏷️"
    @State private var colorHex: String = "#007AFF"
    @State private var startDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var endDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var applyToExistingTransactions: Bool = true
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Основное") {
                    TextField("Название", text: $name)
                        .autocorrectionDisabled()
                    
                    HStack {
                        Text("Иконка")
                        Spacer()
                        TextField("", text: $icon)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    
                    ColorPickerRow(selectedColorHex: $colorHex)
                }
                
                Section("Период") {
                    DatePicker("Начало", selection: $startDate, displayedComponents: .date)
                    DatePicker("Конец", selection: $endDate, displayedComponents: .date)
                }
                
                Section {
                    Toggle("Применить к транзакциям в периоде", isOn: $applyToExistingTransactions)
                    
                    if applyToExistingTransactions {
                        Text("\(affectedTransactionsCount) транзакций будут помечены")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Если включено, все транзакции в выбранном периоде автоматически получат эту метку")
                }
            }
            .navigationTitle("Новая метка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        createTag()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private var affectedTransactionsCount: Int {
        transactions.filter { transaction in
            transaction.date >= startDate && transaction.date <= endDate
        }.count
    }
    
    private func createTag() {
        let tag = TransactionTag(
            name: name.trimmingCharacters(in: .whitespaces),
            startDate: startDate,
            endDate: endDate,
            icon: icon,
            colorHex: colorHex
        )
        
        modelContext.insert(tag)
        
        // Применяем метку к существующим транзакциям, если нужно
        if applyToExistingTransactions {
            for transaction in transactions {
                if transaction.date >= startDate && transaction.date <= endDate {
                    transaction.addTag(tag.name)
                }
            }
        }
        
        dismiss()
    }
}

// MARK: - Edit Tag View

struct EditTagView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    
    let tag: TransactionTag
    
    @State private var name: String = ""
    @State private var icon: String = ""
    @State private var colorHex: String = ""
    @State private var startDate: Date = .now
    @State private var endDate: Date = .now
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Основное") {
                    TextField("Название", text: $name)
                        .autocorrectionDisabled()
                    
                    HStack {
                        Text("Иконка")
                        Spacer()
                        TextField("", text: $icon)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    
                    ColorPickerRow(selectedColorHex: $colorHex)
                }
                
                Section("Период") {
                    DatePicker("Начало", selection: $startDate, displayedComponents: .date)
                    DatePicker("Конец", selection: $endDate, displayedComponents: .date)
                }
                
                Section {
                    HStack {
                        Text("Транзакций с меткой")
                        Spacer()
                        Text("\(transactionCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Редактировать метку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        saveChanges()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                name = tag.name
                icon = tag.icon ?? "🏷️"
                colorHex = tag.colorHex ?? "#007AFF"
                startDate = tag.startDate ?? .now
                endDate = tag.endDate ?? .now
            }
        }
    }
    
    private var transactionCount: Int {
        transactions.filter { $0.tagNames?.contains(tag.name) == true }.count
    }
    
    private func saveChanges() {
        let oldName = tag.name
        let newName = name.trimmingCharacters(in: .whitespaces)
        
        // Если имя изменилось, обновляем его во всех транзакциях
        if oldName != newName {
            for transaction in transactions where transaction.hasTag(oldName) {
                transaction.removeTag(oldName)
                transaction.addTag(newName)
            }
        }
        
        tag.name = newName
        tag.icon = icon
        tag.colorHex = colorHex
        tag.startDate = startDate
        tag.endDate = endDate
        
        dismiss()
    }
}

// MARK: - Color Picker Row

struct ColorPickerRow: View {
    @Binding var selectedColorHex: String
    
    private let colors: [(name: String, hex: String)] = [
        ("Синий", "#007AFF"),
        ("Зеленый", "#34C759"),
        ("Красный", "#FF3B30"),
        ("Оранжевый", "#FF9500"),
        ("Фиолетовый", "#AF52DE"),
        ("Розовый", "#FF2D55"),
        ("Желтый", "#FFCC00"),
        ("Бирюзовый", "#5AC8FA")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Цвет")
                .font(.subheadline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(colors, id: \.hex) { color in
                    Circle()
                        .fill(Color(hex: color.hex))
                        .frame(width: 44, height: 44)
                        .overlay {
                            if selectedColorHex == color.hex {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.white)
                                    .font(.headline)
                            }
                        }
                        .onTapGesture {
                            selectedColorHex = color.hex
                        }
                }
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    TagsManagementView()
        .modelContainer(for: [TransactionTag.self, Transaction.self], inMemory: true)
}
