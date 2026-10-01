import SwiftUI
import SwiftData

/// Метки карточками: эмодзи, период, сколько потрачено. Сверху — предложения
/// по валютам операций: одно касание создаёт метку страны.
struct TagsManagementView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TransactionTag.createdAt, order: .reverse)
    private var tags: [TransactionTag]

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @Query private var settings: [AppSettings]
    @Query private var trackedRates: [TrackedExchangeRate]

    @State private var editorTarget: EditorTarget?
    @State private var tagForTransactions: TransactionTag?
    @State private var tagToDelete: TransactionTag?

    private enum EditorTarget: Identifiable {
        case new
        case edit(TransactionTag)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let tag): return "\(tag.persistentModelID.hashValue)"
            }
        }
    }

    private var suggestions: [CurrencyTagSuggestion] {
        CurrencyTagSuggestions.computeSuggestions(transactions: transactions, existingTags: tags)
    }

    var body: some View {
        let suggestions = suggestions
        let stats = TagStats.make(tags: tags, transactions: transactions, settings: settings.first, trackedRates: trackedRates)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !suggestions.isEmpty {
                    suggestionsSection(suggestions)
                }

                if tags.isEmpty {
                    if suggestions.isEmpty {
                        ContentUnavailableView(
                            "Пока нет меток",
                            systemImage: "tag",
                            description: Text("Метки собирают операции поездки, проекта или события — и показывают, сколько на них ушло.")
                        )
                        .padding(.top, 60)
                    }
                } else {
                    tagsSection(stats: stats)
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Метки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = .new
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Новая метка")
            }
        }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new:
                TagEditorSheet(tag: nil)
            case .edit(let tag):
                TagEditorSheet(tag: tag) { tagToDelete = $0 }
            }
        }
        .navigationDestination(item: $tagForTransactions) { tag in
            TagTransactionsView(tag: tag)
        }
        .confirmationDialog(
            "Удалить метку «\(tagToDelete?.name ?? "")»?",
            isPresented: Binding(get: { tagToDelete != nil }, set: { if !$0 { tagToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let tagToDelete { delete(tagToDelete) }
            }
            Button("Отмена", role: .cancel) { tagToDelete = nil }
        } message: {
            Text("Метка снимется с операций, сами операции останутся.")
        }
    }

    // MARK: - Sections

    private func suggestionsSection(_ suggestions: [CurrencyTagSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Предложения", subtitle: "По валютам операций. Метка будет ставиться сама и на новые траты.")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(suggestions) { suggestion in
                        TagSuggestionCard(suggestion: suggestion) {
                            withAnimation(.snappy(duration: 0.3)) {
                                CurrencyTagSuggestions.createTag(from: suggestion, modelContext: modelContext)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }

    private func tagsSection(stats: [PersistentIdentifier: TagStats]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Мои метки", subtitle: nil)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(tags) { tag in
                    Button {
                        tagForTransactions = tag
                    } label: {
                        TagTile(tag: tag, stats: stats[tag.persistentModelID] ?? .empty)
                    }
                    .buttonStyle(TileButtonStyle())
                    .contextMenu {
                        Button {
                            tagForTransactions = tag
                        } label: {
                            Label("Операции", systemImage: "list.bullet")
                        }
                        Button {
                            editorTarget = .edit(tag)
                        } label: {
                            Label("Изменить", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            tagToDelete = tag
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal)

            Text("Нажми на метку, чтобы открыть её операции. Удерживай — чтобы изменить или удалить.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
        }
    }

    private func sectionHeader(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    private func delete(_ tag: TransactionTag) {
        for transaction in transactions where transaction.hasTag(tag.name) {
            transaction.removeTag(tag.name)
        }
        modelContext.delete(tag)
        try? modelContext.save()
        tagToDelete = nil
    }
}

// MARK: - Stats

/// Сколько операций у метки и сколько по ним потрачено в рублях.
struct TagStats {
    var count = 0
    var spentRub = 0.0

    static let empty = TagStats()

    static func make(
        tags: [TransactionTag],
        transactions: [Transaction],
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate]
    ) -> [PersistentIdentifier: TagStats] {
        let idsByName = Dictionary(tags.map { ($0.name, $0.persistentModelID) }, uniquingKeysWith: { first, _ in first })
        var result: [PersistentIdentifier: TagStats] = [:]
        for transaction in transactions {
            for name in transaction.tagNames ?? [] {
                guard let id = idsByName[name] else { continue }
                result[id, default: .empty].count += 1
                if transaction.kind == .expense {
                    result[id, default: .empty].spentRub += TransactionRubConverter.displayRubAmount(
                        for: transaction,
                        settings: settings,
                        trackedRates: trackedRates
                    ) ?? 0
                }
            }
        }
        return result
    }
}

enum TagFormatting {
    static func operations(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        let word: String
        if mod10 == 1 && mod100 != 11 {
            word = "операция"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            word = "операции"
        } else {
            word = "операций"
        }
        return "\(count) \(word)"
    }

    static func rub(_ value: Double) -> String {
        value.formatted(.currency(code: "RUB").locale(Locale(identifier: "ru_RU")).precision(.fractionLength(0)))
    }

    static func period(of tag: TransactionTag) -> String? {
        guard let start = tag.startDate, let end = tag.endDate else { return nil }
        return CurrencyTagSuggestions.periodDescription(from: start, to: end)
    }
}

// MARK: - Views

/// Иконка метки: эмодзи или SF Symbol (у старых меток), на цветном круге.
struct TagIconView: View {
    let icon: String?
    let colorHex: String?
    var size: CGFloat = 44

    private var color: Color { colorHex.flatMap { Color(hex: $0) } ?? .accentColor }

    private var isEmoji: Bool {
        guard let icon, let first = icon.unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || (icon.unicodeScalars.count > 1 && first.properties.isEmoji)
    }

    var body: some View {
        Circle()
            .fill(color.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                if let icon, isEmoji {
                    Text(icon)
                        .font(.system(size: size * 0.5))
                } else {
                    Image(systemName: icon.flatMap { $0.isEmpty ? nil : $0 } ?? "tag.fill")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(color)
                }
            }
    }
}

private struct TagTile: View {
    let tag: TransactionTag
    let stats: TagStats

    private var color: Color { tag.colorHex.flatMap { Color(hex: $0) } ?? .accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                TagIconView(icon: tag.icon, colorHex: tag.colorHex, size: 44)
                Spacer(minLength: 4)
                if let code = tag.autoCurrencyCode, !code.isEmpty {
                    Label(code, systemImage: "sparkles")
                        .font(.caption2.weight(.bold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(color.opacity(0.14), in: Capsule())
                        .accessibilityLabel("Ставится автоматически по валюте \(code)")
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(TagFormatting.period(of: tag) ?? "Без периода")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 1) {
                Text(TagFormatting.rub(stats.spentRub))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(TagFormatting.operations(stats.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [color.opacity(0.14), color.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct TagSuggestionCard: View {
    let suggestion: CurrencyTagSuggestion
    let onCreate: () -> Void

    private var color: Color { Color(hex: suggestion.info.colorHex) ?? .accentColor }

    var body: some View {
        Button(action: onCreate) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(suggestion.info.icon)
                        .font(.system(size: 30))
                    Spacer()
                    Text(suggestion.info.code)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.info.countryName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(TagFormatting.operations(suggestion.transactionCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label("Создать", systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(color.opacity(0.14), in: Capsule())
                    .foregroundStyle(color)
            }
            .padding(12)
            .frame(width: 140)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(TileButtonStyle())
    }
}

/// Лёгкое «вдавливание» карточки при нажатии.
private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
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
