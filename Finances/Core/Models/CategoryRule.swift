import Foundation
import SwiftData

@Model
final class CategoryRule {
    var pattern: String
    var categoryName: String
    /// Подкатегория, если у категории они есть (например, «Еда» → «Кафе»).
    var subcategoryName: String?
    var priority: Int
    var isEnabled: Bool
    var createdAt: Date

    init(
        pattern: String,
        categoryName: String,
        subcategoryName: String? = nil,
        priority: Int = 0,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.pattern = pattern
        self.categoryName = categoryName
        self.subcategoryName = subcategoryName
        self.priority = priority
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}
