import Testing
import Foundation
@testable import YourAppModule // Замените на имя вашего модуля

@Suite("Category Validation Tests")
struct CategoryValidationTests {
    
    @Test("Guesser возвращает категорию если она существует")
    func testGuesserReturnsExistingCategory() async throws {
        // Arrange
        let categories = [
            ExpenseCategoryItem(name: "Еда", isSystem: true),
            ExpenseCategoryItem(name: "Продукты", isSystem: true),
            ExpenseCategoryItem(name: "Транспорт", isSystem: true)
        ]
        
        let rules: [CategoryRule] = []
        
        // Act
        let result = CategoryRuleEngine.matchCategoryName(
            operationType: "Покупка",
            details: "MCDONALDS MOSCOW",
            rules: rules,
            existingCategories: categories
        )
        
        // Assert
        #expect(result == "Еда")
    }
    
    @Test("Guesser возвращает nil если категория не существует")
    func testGuesserReturnsNilForDeletedCategory() async throws {
        // Arrange - нет категории "Кофе"
        let categories = [
            ExpenseCategoryItem(name: "Еда", isSystem: true),
            ExpenseCategoryItem(name: "Продукты", isSystem: true)
        ]
        
        let rules: [CategoryRule] = []
        
        // Act - транзакция из Starbucks
        let result = CategoryRuleEngine.matchCategoryName(
            operationType: "Покупка",
            details: "STARBUCKS COFFEE",
            rules: rules,
            existingCategories: categories
        )
        
        // Assert - должно быть nil, так как "Кофе" удалена
        #expect(result == nil)
    }
    
    @Test("Правила пользователя имеют приоритет над гессером")
    func testUserRulesOverrideGuesser() async throws {
        // Arrange
        let categories = [
            ExpenseCategoryItem(name: "Еда", isSystem: true),
            ExpenseCategoryItem(name: "Кофе", isSystem: true)
        ]
        
        let rules = [
            CategoryRule(
                pattern: "STARBUCKS",
                categoryName: "Еда", // Переопределяем на "Еда"
                isEnabled: true,
                priority: 100
            )
        ]
        
        // Act
        let result = CategoryRuleEngine.matchCategoryName(
            operationType: "Покупка",
            details: "STARBUCKS COFFEE",
            rules: rules,
            existingCategories: categories
        )
        
        // Assert
        #expect(result == "Еда") // Правило пользователя, не гессер
    }
}
