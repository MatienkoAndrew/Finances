import SwiftUI
import SwiftData

/// Создание и редактирование метки: эмодзи, название, цвет и период.
/// Метка с периодом стоит на всех операциях за эти дни.
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
    /// Валюты поездки; пусто — метка встаёт на все операции за даты.
    @State private var currencyCodes: [String] = []
    @State private var isPickingCurrency = false
    @State private var isPickingEmoji = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    @FocusState private var isNameFocused: Bool

    private static let defaultIcon = "🏷️"

    private var color: Color { Color(hex: colorHex) ?? .accentColor }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var periodTransactions: [Transaction] {
        guard let days = TransactionTagSync.days(from: startDate, to: endDate) else { return [] }
        return transactions.filter { days.contains($0.date) }
    }

    private var periodTransactionCount: Int {
        periodTransactions.count
    }

    /// Валюты расходов за эти дни, чаще встречающиеся — первыми: подсказки для выбора.
    private var suggestedCurrencies: [(code: String, count: Int)] {
        var counts: [String: Int] = [:]
        for transaction in periodTransactions where transaction.kind == .expense {
            for code in TransactionTagSync.paymentCurrencies(of: transaction) {
                counts[code, default: 0] += 1
            }
        }
        return counts
            .filter { !currencyCodes.contains($0.key) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(4)
            .map { (code: $0.key, count: $0.value) }
    }

    /// Сколько операций за даты сразу получат метку и сколько встанут на рассмотрение.
    private var currencySplit: (tagged: Int, review: Int) {
        let currencies = Set(currencyCodes)
        var tagged = 0
        var review = 0
        for transaction in periodTransactions {
            switch TransactionTagSync.decision(for: transaction, currencies: currencies) {
            case .tag: tagged += 1
            case .review: review += 1
            case .skip: break
            }
        }
        return (tagged, review)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    colorCard
                    periodCard

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
                    HStack(alignment: .firstTextBaseline) {
                        Text(TagFormatting.periodDescription(from: startDate, to: endDate))
                            .font(.subheadline.weight(.semibold))
                            .contentTransition(.numericText())
                        Spacer(minLength: 8)
                        Text(TagFormatting.operations(periodTransactionCount))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }

                    DateRangeCalendar(start: $startDate, end: $endDate, tint: color)

                    Divider()

                    currencySection
                }

                Text(periodHint)
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

    private var periodHint: String {
        // Текст не меняется между касаниями по календарю: иначе карточка меняет
        // высоту и календарь съезжает под пальцем.
        if !hasPeriod {
            return "Без дат метку ставишь на операции сам, а период в аналитике берётся по ним."
        }
        if currencyCodes.isEmpty {
            return "Нажми на первый день, потом на последний. Метка встанет на все операции за эти дни — и на новые, добавленные потом."
        }
        return "Операции в выбранных валютах за эти дни получат метку сами. Остальные расходы — например, в долларах или тенге — попадут на рассмотрение: разберёшь их на экране метки. Доходы и переводы в других валютах метку не получат."
    }

    /// Валюты поездки: выбранные — цветом, частые за эти дни — подсказками.
    private var currencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Валюты поездки")
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)

                Button {
                    isPickingCurrency = true
                } label: {
                    Label("Добавить", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
                .tint(color)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(currencyCodes, id: \.self) { code in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                currencyCodes.removeAll { $0 == code }
                            }
                        } label: {
                            currencyChip(code, trailing: "xmark", isSelected: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Убрать \(code)")
                    }

                    ForEach(suggestedCurrencies, id: \.code) { item in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                currencyCodes.append(item.code)
                            }
                        } label: {
                            currencyChip(item.code, trailing: "plus", detail: "\(item.count)", isSelected: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Добавить \(item.code)")
                    }
                }
            }

            if currencyCodes.isEmpty {
                Text("Не выбраны — метка встанет на все операции за даты.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let split = currencySplit
                Text("\(TagFormatting.operations(split.tagged)) в метку · на рассмотрение: \(split.review)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .sheet(isPresented: $isPickingCurrency) {
            CurrencyPickerView(selectedCode: "") { code in
                let normalized = CurrencyDisplay.normalizedCode(from: code)
                guard !currencyCodes.contains(normalized) else { return }
                currencyCodes.append(normalized)
            }
        }
    }

    private func currencyChip(_ code: String, trailing: String, detail: String? = nil, isSelected: Bool) -> some View {
        HStack(spacing: 5) {
            Text(CurrencyDisplay.flag(for: code))
            Text(code)
                .fontWeight(.semibold)
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: trailing)
                .font(.caption2.weight(.bold))
                .foregroundStyle(isSelected ? color : .secondary)
        }
        .font(.subheadline)
        .monospacedDigit()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                Capsule().fill(color.opacity(0.15))
            } else {
                Capsule().strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
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
        currencyCodes = (tag.currencyCodes ?? []).map { CurrencyDisplay.normalizedCode(from: $0) }
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

        let previousStart = tag?.startDate
        let previousEnd = tag?.endDate

        let target: TransactionTag
        if let tag {
            if tag.name != newName {
                for transaction in transactions {
                    transaction.renameTag(tag.name, to: newName)
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
        target.currencyCodes = hasPeriod && !currencyCodes.isEmpty ? currencyCodes : nil

        TransactionTagSync.applyPeriod(
            of: target,
            previousStart: previousStart,
            previousEnd: previousEnd,
            transactions: transactions
        )

        try? modelContext.save()
        dismiss()
    }
}
