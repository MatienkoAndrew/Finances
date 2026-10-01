import Foundation
import SwiftData

@Model
final class ExpenseCategoryItem {
    var name: String
    var iconName: String
    var emoji: String?
    var colorHex: String
    var isSystem: Bool
    var createdAt: Date
    /// Порядок в сетке категорий (долгое нажатие → перетаскивание); nil — в конце, по алфавиту.
    var sortOrder: Int?

    init(
        name: String,
        iconName: String = "square.grid.2x2",
        emoji: String? = nil,
        colorHex: String = "#8E8E93",
        isSystem: Bool = false,
        createdAt: Date = Date()
    ) {
        self.name = name
        self.iconName = iconName
        self.emoji = emoji
        self.colorHex = colorHex
        self.isSystem = isSystem
        self.createdAt = createdAt
    }
}

extension ExpenseCategoryItem {
    /// Категории в пользовательском порядке.
    static func ordered(_ categories: [ExpenseCategoryItem]) -> [ExpenseCategoryItem] {
        categories.sorted {
            ($0.sortOrder ?? Int.max, $0.name.localizedLowercase) < ($1.sortOrder ?? Int.max, $1.name.localizedLowercase)
        }
    }
}
