import Foundation
import SwiftData

@Model
final class ExpenseCategoryItem {
    var name: String
    var iconName: String
    var colorHex: String
    var isSystem: Bool
    var createdAt: Date

    init(
        name: String,
        iconName: String = "square.grid.2x2",
        colorHex: String = "#8E8E93",
        isSystem: Bool = false,
        createdAt: Date = Date()
    ) {
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.isSystem = isSystem
        self.createdAt = createdAt
    }
}
