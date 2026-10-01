import Foundation
import SwiftData

/// Подкатегория расходов: «Еда» → «Кафе и кофейни».
@Model
final class ExpenseSubcategoryItem {
    var name: String
    var emoji: String
    /// Название родительской категории (как `ExpenseCategoryItem.name`).
    var categoryName: String
    var sortOrder: Int
    var createdAt: Date

    init(name: String, emoji: String, categoryName: String, sortOrder: Int, createdAt: Date = Date()) {
        self.name = name
        self.emoji = emoji
        self.categoryName = categoryName
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
