import Foundation
import SwiftData

/// Переход на новую структуру категорий (октябрь 2026):
/// - «Продукты», «Такси», «Аренда Байка», «Общественный транспорт», «Спорт», «Красота»,
///   «Vpn», «Наличка» становятся подкатегориями (или сливаются с системной категорией);
/// - «Здоровье» → «Здоровье и красота», «Подписки» → «Подписки и связь»;
/// - подкатегории переименованы и укрупнены, авиабилеты и поезда переехали в «Транспорт»;
/// - добавлена категория «Развлечения».
/// Затрагивает операции, правила, старые расходы и кэш нейросети; ручной выбор
/// остаётся ручным. Выполняется один раз.
enum CategoryStructureMigration {
    private static let versionKey = "categoryStructureVersion"
    private static let currentVersion = 2

    /// Бывшие категории → куда они переезжают.
    private static let categoryMoves: [String: CategoryMatch] = [
        "продукты": CategoryMatch(category: "Еда", subcategory: "Продукты"),
        "такси": CategoryMatch(category: "Транспорт", subcategory: "Такси"),
        "аренда байка": CategoryMatch(category: "Транспорт", subcategory: "Аренда байка"),
        "общественный транспорт": CategoryMatch(category: "Транспорт", subcategory: "Метро и автобусы"),
        "спорт": CategoryMatch(category: "Здоровье и красота", subcategory: "Спорт и фитнес"),
        "красота": CategoryMatch(category: "Здоровье и красота", subcategory: "Красота"),
        "vpn": CategoryMatch(category: "Подписки и связь", subcategory: "VPN"),
        "наличка": CategoryMatch(category: "Снятие наличных", subcategory: nil)
    ]

    /// Переименованные категории (подкатегории сохраняются и переименовываются ниже).
    private static let categoryRenames: [String: String] = [
        "здоровье": "Здоровье и красота",
        "подписки": "Подписки и связь"
    ]

    /// (категория, старая подкатегория) → новое место.
    private static let subcategoryMoves: [String: [String: CategoryMatch]] = [
        "Еда": [
            "Кафе": .init(category: "Еда", subcategory: "Кафе и кофейни"),
            "Ресторан": .init(category: "Еда", subcategory: "Рестораны"),
            "Бар": .init(category: "Еда", subcategory: "Бары"),
            "Супермаркет": .init(category: "Еда", subcategory: "Продукты")
        ],
        "Транспорт": [
            "Общественный транспорт": .init(category: "Транспорт", subcategory: "Метро и автобусы"),
            "Поезд/электричка": .init(category: "Транспорт", subcategory: "Поезд"),
            "Заправка": .init(category: "Транспорт", subcategory: "Топливо"),
            "Парковка": .init(category: "Транспорт", subcategory: "Другое"),
            "Платные дороги": .init(category: "Транспорт", subcategory: "Другое")
        ],
        "Путешествия": [
            "Авиабилеты": .init(category: "Транспорт", subcategory: "Самолёт"),
            "Ж/д билеты": .init(category: "Транспорт", subcategory: "Поезд"),
            "Аренда авто": .init(category: "Транспорт", subcategory: "Каршеринг"),
            "Виза/страховка": .init(category: "Путешествия", subcategory: "Визы и страховки")
        ],
        "Жильё": [
            "Ипотека": .init(category: "Жильё", subcategory: "Другое"),
            "Ремонт": .init(category: "Жильё", subcategory: "Ремонт и мебель"),
            "Мебель/техника": .init(category: "Жильё", subcategory: "Ремонт и мебель")
        ],
        "Здоровье и красота": [
            "Врач/клиника": .init(category: "Здоровье и красота", subcategory: "Врачи и анализы"),
            "Анализы": .init(category: "Здоровье и красота", subcategory: "Врачи и анализы"),
            "Спорт/фитнес": .init(category: "Здоровье и красота", subcategory: "Спорт и фитнес"),
            "Косметолог": .init(category: "Здоровье и красота", subcategory: "Красота"),
            "Массаж": .init(category: "Здоровье и красота", subcategory: "Массаж и спа")
        ],
        "Покупки": [
            "Одежда": .init(category: "Покупки", subcategory: "Одежда и обувь"),
            "Обувь": .init(category: "Покупки", subcategory: "Одежда и обувь"),
            "Дом/быт": .init(category: "Покупки", subcategory: "Дом и быт"),
            "Подарки": .init(category: "Покупки", subcategory: "Подарки и цветы")
        ],
        "Подписки и связь": [
            "Связь": .init(category: "Подписки и связь", subcategory: "Связь и eSIM"),
            "ИИ": .init(category: "Подписки и связь", subcategory: "Нейросети"),
            "Музыка": .init(category: "Подписки и связь", subcategory: "Музыка и видео")
        ]
    ]

    /// Новое место для пары «категория · подкатегория».
    static func migrated(_ category: String, _ subcategory: String?) -> CategoryMatch {
        let key = CategoryNameNormalizer.normalize(category)

        if let move = categoryMoves[key] {
            return move
        }

        let renamed = categoryRenames[key] ?? category
        if let subcategory, let move = subcategoryMoves[renamed]?[subcategory] {
            return move
        }
        return CategoryMatch(category: renamed, subcategory: subcategory)
    }

    static func runIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: versionKey) < currentVersion else { return }

        guard let categories = try? context.fetch(FetchDescriptor<ExpenseCategoryItem>()),
              let transactions = try? context.fetch(FetchDescriptor<Transaction>()),
              let rules = try? context.fetch(FetchDescriptor<CategoryRule>()),
              let expenses = try? context.fetch(FetchDescriptor<Expense>()) else { return }

        // Новая установка: категории ещё не созданы — сидер создаст уже новые.
        guard !categories.isEmpty else {
            defaults.set(currentVersion, forKey: versionKey)
            return
        }

        // 1. Категории: переименовать, лишние удалить, недостающие добавить.
        for item in categories {
            let key = CategoryNameNormalizer.normalize(item.name)
            if let newName = categoryRenames[key] {
                if categories.contains(where: { CategoryNameNormalizer.normalize($0.name) == CategoryNameNormalizer.normalize(newName) }) {
                    context.delete(item)
                } else {
                    item.name = newName
                }
            } else if categoryMoves[key] != nil {
                context.delete(item)
            }
        }

        let remaining = Set(categories.filter { !$0.isDeleted }.map { CategoryNameNormalizer.normalize($0.name) })
        for definition in DefaultCategoryDefinitions.items where !remaining.contains(CategoryNameNormalizer.normalize(definition.name)) {
            context.insert(ExpenseCategoryItem(
                name: definition.name,
                iconName: definition.iconName,
                colorHex: definition.colorHex,
                isSystem: true
            ))
        }

        // 2. Операции, правила, старые расходы, кэш нейросети.
        for transaction in transactions {
            guard let category = transaction.categoryName else { continue }
            let target = migrated(category, transaction.subcategoryName)
            transaction.categoryName = target.category
            transaction.subcategoryName = target.subcategory
        }

        for rule in rules {
            let target = migrated(rule.categoryName, rule.subcategoryName)
            rule.categoryName = target.category
            rule.subcategoryName = target.subcategory
        }

        for expense in expenses {
            guard let category = expense.categoryName else { continue }
            expense.categoryName = migrated(category, nil).category
        }

        AIMerchantCategoryCache.remap { migrated($0.category, $0.subcategory) }

        do {
            try context.save()
            defaults.set(currentVersion, forKey: versionKey)
        } catch {
            context.rollback()
        }
    }
}
