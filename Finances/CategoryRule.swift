import Foundation
import SwiftData

@Model
final class CategoryRule {
    var pattern: String
    var categoryName: String
    var priority: Int
    var isEnabled: Bool
    var createdAt: Date

    init(
        pattern: String,
        categoryName: String,
        priority: Int = 0,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.pattern = pattern
        self.categoryName = categoryName
        self.priority = priority
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}
