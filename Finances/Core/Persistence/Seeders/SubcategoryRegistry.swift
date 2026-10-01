import Foundation
import Observation
import SwiftData

/// Подкатегории из базы в памяти — для мест, где нужен быстрый синхронный доступ
/// (аналитика, правила, капсулы). Наблюдаемый: экраны перерисуются после правок.
@Observable
final class SubcategoryRegistry {
    static let shared = SubcategoryRegistry()

    /// Нормализованное имя категории → подкатегории по порядку.
    private var byCategory: [String: [DefaultSubcategoryDefinition]]

    private init() {
        // До загрузки из базы — стартовый набор, чтобы первый кадр не был пустым.
        byCategory = Dictionary(
            uniqueKeysWithValues: DefaultSubcategoryDefinitions.seed.map { (CategoryNameNormalizer.normalize($0.key), $0.value) }
        )
    }

    func subcategories(for category: String) -> [DefaultSubcategoryDefinition]? {
        let subs = byCategory[CategoryNameNormalizer.normalize(category)]
        return subs?.isEmpty == false ? subs : nil
    }

    /// Создаёт стартовые подкатегории (если в базе их нет) и загружает всё в память.
    func load(context: ModelContext) {
        let items = (try? context.fetch(FetchDescriptor<ExpenseSubcategoryItem>())) ?? []

        if items.isEmpty {
            let categories = (try? context.fetch(FetchDescriptor<ExpenseCategoryItem>())) ?? []
            for category in categories {
                guard let seed = DefaultSubcategoryDefinitions.seed[category.name] else { continue }
                for (index, sub) in seed.enumerated() {
                    context.insert(ExpenseSubcategoryItem(
                        name: sub.name,
                        emoji: sub.emoji,
                        categoryName: category.name,
                        sortOrder: index
                    ))
                }
            }
            try? context.save()
        }

        reload(context: context)
    }

    func reload(context: ModelContext) {
        let items = (try? context.fetch(FetchDescriptor<ExpenseSubcategoryItem>())) ?? []
        byCategory = Dictionary(grouping: items) { CategoryNameNormalizer.normalize($0.categoryName) }
            .mapValues { group in
                group.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
                    .map { DefaultSubcategoryDefinition(name: $0.name, emoji: $0.emoji) }
            }
    }
}
