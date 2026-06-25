import Foundation

/// Встроенное правило автоматической категоризации
struct BuiltInCategoryRule: Identifiable, Codable {
    let id: String
    let pattern: String
    let categoryName: String
    let description: String
    var isEnabled: Bool
    
    init(id: String, pattern: String, categoryName: String, description: String, isEnabled: Bool = true) {
        self.id = id
        self.pattern = pattern
        self.categoryName = categoryName
        self.description = description
        self.isEnabled = isEnabled
    }
}

/// Менеджер встроенных правил категоризации
enum BuiltInCategoryRulesManager {
    private static let storageKey = "builtInCategoryRulesStates"
    
    /// Все доступные встроенные правила
    static let allRules: [BuiltInCategoryRule] = [
        // Подписки
        BuiltInCategoryRule(
            id: "chatgpt",
            pattern: "CHATGPT",
            categoryName: "Подписки",
            description: "ChatGPT и OpenAI"
        ),
        BuiltInCategoryRule(
            id: "spotify",
            pattern: "SPOTIFY",
            categoryName: "Подписки",
            description: "Spotify"
        ),
        BuiltInCategoryRule(
            id: "apple",
            pattern: "APPLE.COM BILL",
            categoryName: "Подписки",
            description: "Apple сервисы"
        ),
        
        // Транспорт
        BuiltInCategoryRule(
            id: "grab",
            pattern: "GRAB",
            categoryName: "Транспорт",
            description: "Grab (такси, доставка)"
        ),
        
        // Еда
        BuiltInCategoryRule(
            id: "mcdonalds",
            pattern: "MCDONALDS",
            categoryName: "Еда",
            description: "McDonald's"
        ),
        BuiltInCategoryRule(
            id: "coffee",
            pattern: "COFFEE",
            categoryName: "Еда",
            description: "Кофейни (общее)"
        ),
        BuiltInCategoryRule(
            id: "starbucks",
            pattern: "STARBUCKS",
            categoryName: "Еда",
            description: "Starbucks"
        ),
        BuiltInCategoryRule(
            id: "highlands",
            pattern: "HIGHLANDS",
            categoryName: "Еда",
            description: "Highlands Coffee"
        ),
        
        // Продукты
        BuiltInCategoryRule(
            id: "mart",
            pattern: "MART",
            categoryName: "Продукты",
            description: "Магазины (Mart, Market)"
        ),
        
        // Путешествия
        BuiltInCategoryRule(
            id: "agoda",
            pattern: "AGODA",
            categoryName: "Путешествия",
            description: "Agoda (бронирование)"
        ),
        BuiltInCategoryRule(
            id: "hotel",
            pattern: "HOTEL",
            categoryName: "Путешествия",
            description: "Отели"
        ),
        
        // Здоровье
        BuiltInCategoryRule(
            id: "fitness",
            pattern: "FITNESS",
            categoryName: "Здоровье",
            description: "Фитнес и спорт"
        ),
        
        // Покупки
        BuiltInCategoryRule(
            id: "element",
            pattern: "ELEMENT",
            categoryName: "Покупки",
            description: "Магазины и покупки"
        )
    ]
    
    /// Загрузить состояния правил из UserDefaults
    static func loadStates() -> [String: Bool] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let states = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return [:]
        }
        return states
    }
    
    /// Сохранить состояния правил в UserDefaults
    static func saveStates(_ states: [String: Bool]) {
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    /// Получить активные правила с учётом настроек пользователя
    static func getActiveRules() -> [BuiltInCategoryRule] {
        let states = loadStates()
        return allRules.map { rule in
            var mutableRule = rule
            if let savedState = states[rule.id] {
                mutableRule.isEnabled = savedState
            }
            return mutableRule
        }.filter { $0.isEnabled }
    }
    
    /// Обновить состояние конкретного правила
    static func updateRuleState(id: String, isEnabled: Bool) {
        var states = loadStates()
        states[id] = isEnabled
        saveStates(states)
    }
}
