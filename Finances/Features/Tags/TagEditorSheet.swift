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
    @State private var isPickingEmoji = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    @FocusState private var isNameFocused: Bool

    private static let defaultIcon = "🏷️"

    private var color: Color { Color(hex: colorHex) ?? .accentColor }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var periodTransactionCount: Int {
        guard let days = TransactionTagSync.days(from: startDate, to: endDate) else { return 0 }
        return transactions.filter { days.contains($0.date) }.count
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
        // Текст не меняется между касаниями: иначе карточка меняет высоту
        // и календарь съезжает под пальцем.
        hasPeriod
            ? "Нажми на первый день, потом на последний. Метка встанет на все операции за эти дни — и на новые, добавленные потом."
            : "Без дат метку ставишь на операции сам, а период в аналитике берётся по ним."
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
