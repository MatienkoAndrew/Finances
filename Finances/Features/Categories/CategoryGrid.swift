import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Ячейка категории в сетке: цветной круг, бейдж (подкатегории / выбрано / удалить) и название.
struct CategoryGridCell: View {
    let category: ExpenseCategoryItem
    var isHighlighted = false
    var isExpanded = false
    var showsCheckmark = false
    var isEditing = false
    var onDelete: (() -> Void)?

    private var color: Color { Color(hex: category.colorHex) ?? .gray }
    private var hasSubcategories: Bool { DefaultSubcategoryDefinitions.hasSubcategories(category.name) }

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                CategoryIconView(category: category, size: 50)
                    .padding(4)
                    .overlay {
                        Circle()
                            .strokeBorder(color, lineWidth: isHighlighted || isExpanded ? 2 : 0)
                    }

                if !isEditing {
                    if hasSubcategories {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(color)
                            .frame(width: 18, height: 18)
                            .background(Color(.systemBackground), in: Circle())
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    } else if showsCheckmark {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(color, in: Circle())
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if isEditing, let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.primary)
                            .frame(width: 22, height: 22)
                            .background(.regularMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .offset(x: -2, y: -2)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Удалить \(category.name)")
                }
            }

            Text(category.name)
                .font(.caption.weight(isHighlighted ? .semibold : .regular))
                .foregroundStyle(isHighlighted ? color : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .wiggling(isEditing)
    }
}

/// Покачивание, как у иконок на домашнем экране в режиме правки.
private struct WiggleModifier: ViewModifier {
    let isActive: Bool
    @State private var tilt = false
    @State private var delay = Double.random(in: 0...0.12)

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isActive ? (tilt ? 2.2 : -2.2) : 0))
            .animation(
                isActive
                    ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true).delay(delay)
                    : .easeOut(duration: 0.15),
                value: tilt
            )
            .onChange(of: isActive, initial: true) { _, active in
                tilt = active
            }
    }
}

extension View {
    func wiggling(_ isActive: Bool) -> some View {
        modifier(WiggleModifier(isActive: isActive))
    }
}

/// Сетка категорий в режиме правки: покачиваются, перетаскиваются, по желанию удаляются.
/// Порядок сохраняется в `sortOrder` после каждого перетаскивания.
struct ReorderableCategoryGrid: View {
    @Environment(\.modelContext) private var modelContext

    let categories: [ExpenseCategoryItem]
    var columns = 4
    var onDelete: ((ExpenseCategoryItem) -> Void)?

    @State private var items: [ExpenseCategoryItem] = []
    @State private var dragging: ExpenseCategoryItem?

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 14) {
            ForEach(items) { category in
                CategoryGridCell(
                    category: category,
                    isEditing: true,
                    onDelete: onDelete.map { handler in { handler(category) } }
                )
                .onDrag {
                    dragging = category
                    return NSItemProvider(object: category.name as NSString)
                }
                .onDrop(of: [.text], delegate: CategoryReorderDropDelegate(
                    target: category,
                    items: $items,
                    dragging: $dragging,
                    onCommit: saveOrder
                ))
            }
        }
        // Отпустили не над ячейкой — всё равно завершаем перетаскивание.
        .onDrop(of: [.text], isTargeted: nil) { _ in
            dragging = nil
            saveOrder()
            return true
        }
        .onAppear { items = categories }
        .onChange(of: categories.map(\.persistentModelID)) { _, _ in
            // Категорию удалили или добавили — берём новый список, сохраняя наш порядок.
            items = categories
        }
        .onDisappear(perform: saveOrder)
    }

    private func saveOrder() {
        for (index, category) in items.enumerated() where !category.isDeleted && category.sortOrder != index {
            category.sortOrder = index
        }
        try? modelContext.save()
    }
}

private struct CategoryReorderDropDelegate: DropDelegate {
    let target: ExpenseCategoryItem
    @Binding var items: [ExpenseCategoryItem]
    @Binding var dragging: ExpenseCategoryItem?
    let onCommit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = items.firstIndex(of: dragging),
              let to = items.firstIndex(of: target) else { return }

        withAnimation(.snappy(duration: 0.22)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        // Палец ушёл с ячейки — порядок уже обновлён, сохраняем его.
        onCommit()
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        onCommit()
        return true
    }
}
