import SwiftUI
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
    
    private var suggestions: [CurrencyTagSuggestion] {
        CurrencyTagSuggestions.computeSuggestions(
            transactions: transactions,
            existingTags: tags
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions) { suggestion in
                            SuggestionRowView(suggestion: suggestion) {
                                applySuggestion(suggestion)
                            }
                        }
                    } header: {
                        Text("Умные метки")
                    } footer: {
                        Text("Подсказки на основе валют ваших транзакций. Тап создаёт метку и применяет её ко всем подходящим тратам — а в будущем она будет ставиться автоматически.")
                    }
                }

                if tags.isEmpty && suggestions.isEmpty {
                    ContentUnavailableView(
                        "Нет меток",
                        systemImage: "tag.slash",
                        description: Text("Создайте метку для группировки транзакций по странам, проектам или событиям")
                    )
                } else if !tags.isEmpty {
                    Section("Ваши метки") {
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

    private func applySuggestion(_ suggestion: CurrencyTagSuggestion) {
        CurrencyTagSuggestions.createTag(
            from: suggestion,
            transactions: transactions,
            modelContext: modelContext
        )
    }
}

// MARK: - Suggestion Row

struct SuggestionRowView: View {
    let suggestion: CurrencyTagSuggestion
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(suggestion.info.icon)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(ColorHelper.fromHex(suggestion.info.colorHex).opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(suggestion.info.countryName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(suggestion.info.code)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(.secondary.opacity(0.15))
                            )
                            .foregroundStyle(.secondary)
                    }

                    Text("\(suggestion.transactionCount) транзакций · \(CurrencyTagSuggestions.periodDescription(from: suggestion.firstDate, to: suggestion.lastDate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                        .fill(ColorHelper.fromHex(tag.colorHex ?? "#007AFF").opacity(0.15))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tag.name)
                        .font(.headline)

                    if let code = tag.autoCurrencyCode, !code.isEmpty {
                        Label("Авто \(code)", systemImage: "sparkles")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.15))
                            )
                            .foregroundStyle(Color.accentColor)
                    }
                }

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
    @State private var autoCurrencyEnabled: Bool = false
    @State private var autoCurrencyCode: String = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Список ISO-кодов валют, известных «умным меткам».
    private var availableAutoCurrencyCodes: [String] {
        CurrencyTagSuggestions.countryByCurrency.keys.sorted()
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
                    Toggle("Применять автоматически по валюте", isOn: $autoCurrencyEnabled)

                    if autoCurrencyEnabled {
                        Picker("Валюта", selection: $autoCurrencyCode) {
                            Text("Не выбрана").tag("")
                            ForEach(availableAutoCurrencyCodes, id: \.self) { code in
                                let info = CurrencyTagSuggestions.countryByCurrency[code]
                                let label = info.map { "\($0.icon) \(code) — \($0.countryName)" } ?? code
                                Text(label).tag(code)
                            }
                        }
                    }
                } footer: {
                    if autoCurrencyEnabled, !autoCurrencyCode.isEmpty {
                        Text("Метка будет автоматически добавляться к будущим транзакциям в валюте \(autoCurrencyCode).")
                    } else {
                        Text("Включите, чтобы метка ставилась сама на новые транзакции в выбранной валюте (например, HKD → Гонконг).")
                    }
                }

                Section {
                    NavigationLink {
                        TagTransactionsView(tag: tag)
                    } label: {
                        HStack {
                            Text("Транзакций с меткой")
                            Spacer()
                            Text("\(transactionCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Откройте, чтобы посмотреть все транзакции метки и быстро убрать ненужные.")
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
                if let code = tag.autoCurrencyCode, !code.isEmpty {
                    autoCurrencyEnabled = true
                    autoCurrencyCode = code
                } else {
                    autoCurrencyEnabled = false
                    autoCurrencyCode = ""
                }
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

        // Сохраняем настройки авто-применения по валюте.
        // Если пользователь включил тогл и выбрал валюту — записываем; иначе чистим поле.
        let trimmedCode = autoCurrencyCode.trimmingCharacters(in: .whitespaces).uppercased()
        let newAutoCode = (autoCurrencyEnabled && !trimmedCode.isEmpty) ? trimmedCode : nil
        let oldAutoCode = tag.autoCurrencyCode
        tag.autoCurrencyCode = newAutoCode

        // Если только что включили авто-валюту — сразу применяем метку ретроспективно
        // ко всем подходящим транзакциям, чтобы пользователь не остался с пустой меткой.
        if let code = newAutoCode, code != oldAutoCode {
            for tx in transactions where tx.kind != .transfer {
                guard let txCode = CurrencyTagSuggestions.merchantCurrency(of: tx) else { continue }
                if txCode == code, !tx.hasTag(tag.name) {
                    tx.addTag(tag.name)
                }
            }
        }

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
                        .fill(ColorHelper.fromHex(color.hex))
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

// MARK: - Color Helper

struct ColorHelper {
    static func fromHex(_ hex: String) -> Color {
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

        return Color(
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
