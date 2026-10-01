import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Создание и редактирование категории: название, иконка или эмодзи, цвет и подкатегории.
/// Переименования и удаления подкатегорий переносятся на операции, правила и догадки нейросети.
struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allCategories: [ExpenseCategoryItem]

    /// nil — новая категория.
    let category: ExpenseCategoryItem?
    var onSaved: ((String) -> Void)?
    var onDelete: ((ExpenseCategoryItem) -> Void)?

    @State private var name = ""
    @State private var iconName = CategoryAppearance.iconOptions.first ?? "square.grid.2x2.fill"
    @State private var emoji = ""
    @State private var colorHex = CategoryAppearance.colorOptions.first ?? "#FF3B30"
    @State private var subcategories: [SubcategoryDraft] = []
    @State private var draggingSubcategory: SubcategoryDraft?
    @State private var emojiTarget: EmojiTarget?
    @State private var errorMessage: String?
    @State private var didLoad = false

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case subcategory(UUID)
    }

    private enum EmojiTarget: Identifiable {
        case category
        case subcategory(UUID)

        var id: String {
            switch self {
            case .category: return "category"
            case .subcategory(let id): return id.uuidString
            }
        }
    }

    struct SubcategoryDraft: Identifiable, Equatable {
        let id = UUID()
        var itemID: PersistentIdentifier?
        var originalName: String?
        var name: String
        var emoji: String
    }

    private var color: Color { Color(hex: colorHex) ?? .gray }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    subcategoriesCard
                    colorCard
                    iconCard

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if let category, let onDelete {
                        Button("Удалить категорию", role: .destructive) {
                            dismiss()
                            onDelete(category)
                        }
                        .font(.subheadline)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(category == nil ? "Новая категория" : "Категория")
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
            .sheet(item: $emojiTarget) { target in
                EmojiPickerSheet(selectedEmoji: emojiBinding(for: target))
            }
        }
        .presentationCornerRadius(28)
        .onAppear(perform: load)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 14) {
            Button {
                emojiTarget = .category
            } label: {
                Circle()
                    .fill(color.gradient)
                    .frame(width: 96, height: 96)
                    .overlay {
                        if emoji.isEmpty {
                            Image(systemName: iconName)
                                .font(.system(size: 38, weight: .semibold))
                                .foregroundStyle(.white)
                        } else {
                            Text(emoji)
                                .font(.system(size: 46))
                        }
                    }
                    .shadow(color: color.opacity(0.35), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .animation(.snappy(duration: 0.2), value: colorHex)

            TextField("Название", text: $name)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .focused($focusedField, equals: .name)
                .submitLabel(.done)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var iconCard: some View {
        card("Иконка") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                Button {
                    emojiTarget = .category
                } label: {
                    iconCell(isSelected: !emoji.isEmpty) {
                        Text(emoji.isEmpty ? "😀" : emoji)
                            .font(.system(size: 20))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Эмодзи")

                ForEach(CategoryAppearance.iconOptions, id: \.self) { symbol in
                    Button {
                        iconName = symbol
                        emoji = ""
                    } label: {
                        iconCell(isSelected: emoji.isEmpty && iconName == symbol) {
                            Image(systemName: symbol)
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func iconCell<Content: View>(isSelected: Bool, @ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? AnyShapeStyle(color) : AnyShapeStyle(Color(.tertiarySystemFill)))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                content()
                    .foregroundStyle(isSelected ? .white : .primary)
            }
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

    private var subcategoriesCard: some View {
        card("Подкатегории", trailing: subcategories.isEmpty ? nil : "\(subcategories.count)") {
            VStack(spacing: 8) {
                ForEach($subcategories) { $draft in
                    subcategoryRow($draft)
                        .opacity(draggingSubcategory?.id == draft.id ? 0.4 : 1)
                        .onDrop(of: [.text], delegate: SubcategoryDropDelegate(
                            target: draft,
                            items: $subcategories,
                            dragging: $draggingSubcategory
                        ))
                }

                Button(action: addSubcategory) {
                    Label("Добавить подкатегорию", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)

                Text(subcategories.isEmpty
                     ? "Без подкатегорий категория выбирается одним касанием."
                     : "Операции без подкатегории попадают в «Другое». Порядок меняется перетаскиванием за ≡.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func subcategoryRow(_ draft: Binding<SubcategoryDraft>) -> some View {
        HStack(spacing: 10) {
            Button {
                emojiTarget = .subcategory(draft.wrappedValue.id)
            } label: {
                Text(draft.wrappedValue.emoji)
                    .font(.system(size: 20))
                    .frame(width: 38, height: 38)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            TextField("Подкатегория", text: draft.name)
                .focused($focusedField, equals: .subcategory(draft.wrappedValue.id))
                .submitLabel(.done)

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    subcategories.removeAll { $0.id == draft.wrappedValue.id }
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white, .red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Удалить подкатегорию")

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 28, height: 38)
                .contentShape(Rectangle())
                .onDrag {
                    draggingSubcategory = draft.wrappedValue
                    return NSItemProvider(object: draft.wrappedValue.id.uuidString as NSString)
                }
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        }
    }

    private func card<Content: View>(
        _ title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - State

    private func emojiBinding(for target: EmojiTarget) -> Binding<String> {
        switch target {
        case .category:
            return $emoji
        case .subcategory(let id):
            return Binding(
                get: { subcategories.first { $0.id == id }?.emoji ?? "" },
                set: { newValue in
                    guard let index = subcategories.firstIndex(where: { $0.id == id }) else { return }
                    subcategories[index].emoji = newValue.isEmpty ? "🏷️" : newValue
                }
            )
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        guard let category else {
            focusedField = .name
            return
        }

        name = category.name
        iconName = category.iconName
        emoji = category.emoji ?? ""
        colorHex = category.colorHex
        subcategories = subcategoryItems(of: category.name).map {
            SubcategoryDraft(itemID: $0.persistentModelID, originalName: $0.name, name: $0.name, emoji: $0.emoji)
        }
    }

    private func addSubcategory() {
        let draft = SubcategoryDraft(name: "", emoji: "🏷️")
        // Новая подкатегория — перед «Другим», которое логично держать последним.
        let otherIndex = subcategories.firstIndex { $0.name == DefaultSubcategoryDefinitions.defaultName }
        withAnimation(.snappy(duration: 0.2)) {
            subcategories.insert(draft, at: otherIndex ?? subcategories.endIndex)
        }
        focusedField = .subcategory(draft.id)
    }

    private func subcategoryItems(of categoryName: String) -> [ExpenseSubcategoryItem] {
        let key = CategoryNameNormalizer.normalize(categoryName)
        let items = (try? modelContext.fetch(FetchDescriptor<ExpenseSubcategoryItem>())) ?? []
        return items
            .filter { CategoryNameNormalizer.normalize($0.categoryName) == key }
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    // MARK: - Save

    private func save() {
        let newName = trimmedName
        guard !newName.isEmpty else { return }

        let duplicate = allCategories.contains { item in
            item.persistentModelID != category?.persistentModelID
                && CategoryNameNormalizer.normalize(item.name) == CategoryNameNormalizer.normalize(newName)
        }
        guard !duplicate else {
            errorMessage = "Категория «\(newName)» уже есть."
            return
        }

        let transactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
        let rules = (try? modelContext.fetch(FetchDescriptor<CategoryRule>())) ?? []
        let oldName = category?.name ?? newName
        let existingItems = category.map { subcategoryItems(of: $0.name) } ?? []

        // 1. Сама категория.
        let target: ExpenseCategoryItem
        if let category {
            if oldName != newName {
                let expenses = (try? modelContext.fetch(FetchDescriptor<Expense>())) ?? []
                TransactionCategorySync.renameCategory(
                    from: oldName,
                    to: newName,
                    transactions: transactions,
                    legacyExpenses: expenses,
                    rules: rules
                )
                AIMerchantCategoryCache.remap { match in
                    match.category == oldName ? CategoryMatch(category: newName, subcategory: match.subcategory) : match
                }
            }
            target = category
        } else {
            target = ExpenseCategoryItem(name: newName)
            target.sortOrder = (allCategories.compactMap(\.sortOrder).max() ?? allCategories.count) + 1
            modelContext.insert(target)
        }
        target.name = newName
        target.iconName = iconName
        target.emoji = emoji.isEmpty ? nil : emoji
        target.colorHex = colorHex

        // 2. Подкатегории: пустые и повторы отбрасываем, «Другое» держим, если есть хоть одна.
        var seen = Set<String>()
        var drafts = subcategories.compactMap { draft -> SubcategoryDraft? in
            var draft = draft
            draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !draft.name.isEmpty, seen.insert(draft.name.lowercased()).inserted else { return nil }
            return draft
        }
        if !drafts.isEmpty, !drafts.contains(where: { $0.name == DefaultSubcategoryDefinitions.defaultName }) {
            drafts.append(SubcategoryDraft(name: DefaultSubcategoryDefinitions.defaultName, emoji: "🧩"))
        }

        var renamed: [String: String?] = [:]
        for item in existingItems {
            if let draft = drafts.first(where: { $0.itemID == item.persistentModelID }) {
                if item.name != draft.name { renamed[item.name] = draft.name }
            } else {
                renamed[item.name] = .some(nil)
                modelContext.delete(item)
            }
        }

        for (index, draft) in drafts.enumerated() {
            if let itemID = draft.itemID, let item = existingItems.first(where: { $0.persistentModelID == itemID }) {
                item.name = draft.name
                item.emoji = draft.emoji
                item.categoryName = newName
                item.sortOrder = index
            } else {
                modelContext.insert(ExpenseSubcategoryItem(
                    name: draft.name,
                    emoji: draft.emoji,
                    categoryName: newName,
                    sortOrder: index
                ))
            }
        }

        // 3. Переименованные и удалённые подкатегории — в операциях, правилах и догадках.
        if !renamed.isEmpty {
            for transaction in transactions where transaction.categoryName == newName {
                if let sub = transaction.subcategoryName, let replacement = renamed[sub] {
                    transaction.subcategoryName = replacement
                }
            }
            for rule in rules where rule.categoryName == newName {
                if let sub = rule.subcategoryName, let replacement = renamed[sub] {
                    rule.subcategoryName = replacement
                }
            }
            AIMerchantCategoryCache.remap { match in
                guard match.category == newName, let sub = match.subcategory, let replacement = renamed[sub] else { return match }
                return CategoryMatch(category: newName, subcategory: replacement)
            }
        }

        do {
            try modelContext.save()
            SubcategoryRegistry.shared.reload(context: modelContext)
            onSaved?(newName)
            dismiss()
        } catch {
            errorMessage = "Не удалось сохранить."
        }
    }
}

private struct SubcategoryDropDelegate: DropDelegate {
    let target: CategoryEditorSheet.SubcategoryDraft
    @Binding var items: [CategoryEditorSheet.SubcategoryDraft]
    @Binding var dragging: CategoryEditorSheet.SubcategoryDraft?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != target.id,
              let from = items.firstIndex(where: { $0.id == dragging.id }),
              let to = items.firstIndex(where: { $0.id == target.id }) else { return }

        withAnimation(.snappy(duration: 0.2)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
