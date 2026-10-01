import SwiftUI
import SwiftData

/// Создание и редактирование метки: эмодзи, название, цвет, период и авто-метка по валюте.
struct TagEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allTags: [TransactionTag]
    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    /// nil — новая метка.
    let tag: TransactionTag?
    var onDelete: ((TransactionTag) -> Void)?

    @State private var name = ""
    @State private var icon = TagEditorSheet.defaultIcon
    @State private var colorHex = "#007AFF"
    @State private var hasPeriod = false
    @State private var startDate = Calendar.current.startOfDay(for: .now)
    @State private var endDate = Calendar.current.startOfDay(for: .now)
    @State private var applyToPeriod = true
    @State private var autoCurrencyCode = ""
    @State private var isPickingEmoji = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    @FocusState private var isNameFocused: Bool

    private static let defaultIcon = "🏷️"

    private var color: Color { Color(hex: colorHex) ?? .accentColor }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var currencyOptions: [CurrencyCountryInfo] {
        CurrencyTagSuggestions.countryByCurrency.values.sorted { $0.countryName < $1.countryName }
    }

    private var periodTransactionCount: Int {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        return transactions.filter { $0.date >= startDate && $0.date < end }.count
    }

    private var currencyTransactionCount: Int {
        guard !autoCurrencyCode.isEmpty else { return 0 }
        return transactions.filter {
            $0.kind != .transfer && CurrencyTagSuggestions.merchantCurrency(of: $0) == autoCurrencyCode
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    colorCard
                    periodCard
                    autoCurrencyCard

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if let tag, let onDelete {
                        Button("Удалить метку", role: .destructive) {
                            dismiss()
                            onDelete(tag)
                        }
                        .font(.subheadline)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(tag == nil ? "Новая метка" : "Метка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .sheet(isPresented: $isPickingEmoji) {
                EmojiPickerSheet(selectedEmoji: Binding(
                    get: { icon },
                    set: { icon = $0.isEmpty ? Self.defaultIcon : $0 }
                ))
            }
        }
        .presentationCornerRadius(28)
        .onAppear(perform: load)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 14) {
            Button {
                isPickingEmoji = true
            } label: {
                TagIconView(icon: icon, colorHex: colorHex, size: 96)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(width: 28, height: 28)
                            .background(Color(.secondarySystemGroupedBackground), in: Circle())
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Выбрать эмодзи")
            .animation(.snappy(duration: 0.2), value: colorHex)

            TextField("Название", text: $name)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .focused($isNameFocused)
                .submitLabel(.done)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var colorCard: some View {
        card("Цвет") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 10) {
                ForEach(CategoryAppearance.colorOptions, id: \.self) { hex in
                    Button {
                        colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                if colorHex == hex {
                                    Circle().strokeBorder(.white, lineWidth: 3)
                                    Circle().strokeBorder(Color(hex: hex) ?? .gray, lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var periodCard: some View {
        card("Период") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Даты поездки или события", isOn: $hasPeriod.animation(.snappy(duration: 0.2)))
                    .tint(color)

                if hasPeriod {
                    HStack(spacing: 10) {
                        datePill("С", selection: $startDate)
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        datePill("По", selection: $endDate)
                    }

                    if tag == nil {
                        Toggle(isOn: $applyToPeriod) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Отметить операции за период")
                                Text(TagFormatting.operations(periodTransactionCount))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(color)
                    }
                }

                Text(hasPeriod
                     ? "Даты задают рамки графика в аналитике метки."
                     : "Без дат период в аналитике берётся по самим операциям.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue { endDate = newValue }
        }
        .onChange(of: endDate) { _, newValue in
            if startDate > newValue { startDate = newValue }
        }
    }

    private func datePill(_ title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker(title, selection: selection, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var autoCurrencyCard: some View {
        card("Автоматически") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("По валюте")
                    Spacer()
                    Menu {
                        Button("Не ставить") { autoCurrencyCode = "" }
                        Divider()
                        ForEach(currencyOptions, id: \.code) { info in
                            Button("\(info.icon) \(info.countryName) · \(info.code)") {
                                autoCurrencyCode = info.code
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(currencyLabel)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(color.opacity(autoCurrencyCode.isEmpty ? 0.08 : 0.15), in: Capsule())
                        .foregroundStyle(autoCurrencyCode.isEmpty ? Color.secondary : color)
                    }
                }

                Text(autoCurrencyCode.isEmpty
                     ? "Выбери валюту — и метка будет сама ставиться на траты в ней, например THB → Таиланд."
                     : "Метка встанет на \(TagFormatting.operations(currencyTransactionCount)) в \(autoCurrencyCode) и на все новые.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var currencyLabel: String {
        guard !autoCurrencyCode.isEmpty else { return "Не ставить" }
        if let info = CurrencyTagSuggestions.countryByCurrency[autoCurrencyCode] {
            return "\(info.icon) \(info.code)"
        }
        return autoCurrencyCode
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - State

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        guard let tag else {
            colorHex = CategoryAppearance.colorOptions.randomElement() ?? colorHex
            // Шторка ещё выезжает — фокус сразу не встанет.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { isNameFocused = true }
            return
        }
        name = tag.name
        icon = tag.icon.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultIcon
        colorHex = tag.colorHex ?? colorHex
        if let start = tag.startDate, let end = tag.endDate {
            hasPeriod = true
            startDate = start
            endDate = end
        }
        autoCurrencyCode = tag.autoCurrencyCode ?? ""
    }

    private func save() {
        let newName = trimmedName
        guard !newName.isEmpty else { return }

        let isTaken = allTags.contains {
            $0.persistentModelID != tag?.persistentModelID
                && $0.name.compare(newName, options: .caseInsensitive) == .orderedSame
        }
        guard !isTaken else {
            errorMessage = "Метка «\(newName)» уже есть."
            return
        }

        let target: TransactionTag
        if let tag {
            if tag.name != newName {
                for transaction in transactions where transaction.hasTag(tag.name) {
                    transaction.tagNames = transaction.tagNames?.map { $0 == tag.name ? newName : $0 }
                }
                for transaction in transactions where transaction.isTagManuallyExcluded(tag.name) {
                    transaction.manuallyExcludedTagNames = transaction.manuallyExcludedTagNames?.map { $0 == tag.name ? newName : $0 }
                }
            }
            target = tag
            target.name = newName
        } else {
            target = TransactionTag(name: newName)
            modelContext.insert(target)
        }

        target.icon = icon
        target.colorHex = colorHex
        target.startDate = hasPeriod ? startDate : nil
        target.endDate = hasPeriod ? endDate : nil

        let oldCode = tag?.autoCurrencyCode
        target.autoCurrencyCode = autoCurrencyCode.isEmpty ? nil : autoCurrencyCode

        // Новая метка с периодом — сразу отмечаем операции за эти дни.
        if tag == nil, hasPeriod, applyToPeriod {
            let end = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
            for transaction in transactions where transaction.date >= startDate && transaction.date < end {
                transaction.addTag(newName)
            }
        }

        // Включили авто-валюту — ставим метку и на прошлые операции в этой валюте.
        if let code = target.autoCurrencyCode, code != oldCode {
            for transaction in transactions where transaction.kind != .transfer
                && CurrencyTagSuggestions.merchantCurrency(of: transaction) == code
                && !transaction.isTagManuallyExcluded(newName) {
                transaction.addTag(newName)
            }
        }

        try? modelContext.save()
        dismiss()
    }
}
