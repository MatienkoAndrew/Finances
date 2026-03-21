import Foundation
import SwiftData

enum CategorySeeder {
    static func seedIfNeeded(existing: [ExpenseCategoryItem], modelContext: ModelContext) {
        guard existing.isEmpty else { return }

        for item in DefaultCategoryDefinitions.items {
            let category = ExpenseCategoryItem(
                name: item.name,
                iconName: item.iconName,
                colorHex: item.colorHex,
                isSystem: true
            )
            modelContext.insert(category)
        }
    }
}
