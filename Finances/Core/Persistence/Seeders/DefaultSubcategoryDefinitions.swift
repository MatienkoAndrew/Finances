//
//  DefaultSubcategoryDefinitions.swift
//  Finances
//
//  Подкатегории внутри категорий. Здесь — стартовый набор; дальше подкатегории
//  живут в базе (`ExpenseSubcategoryItem`) и редактируются пользователем,
//  а читаются через `SubcategoryRegistry`.
//

import Foundation

struct DefaultSubcategoryDefinition: Identifiable, Hashable {
    let name: String
    let emoji: String

    var id: String { name }
}

enum DefaultSubcategoryDefinitions {
    /// Имя подкатегории, выбираемой по умолчанию при выборе категории с подкатегориями.
    static let defaultName = "Другое"

    static let seed: [String: [DefaultSubcategoryDefinition]] = [
        "Еда": [
            .init(name: "Продукты", emoji: "🛒"),
            .init(name: "Кафе и кофейни", emoji: "☕️"),
            .init(name: "Рестораны", emoji: "🍽️"),
            .init(name: "Фастфуд", emoji: "🍔"),
            .init(name: "Доставка", emoji: "🛵"),
            .init(name: "Бары", emoji: "🍺"),
            .init(name: "Другое", emoji: "🍴")
        ],
        "Транспорт": [
            .init(name: "Такси", emoji: "🚕"),
            .init(name: "Метро и автобусы", emoji: "🚇"),
            .init(name: "Поезд", emoji: "🚆"),
            .init(name: "Самолёт", emoji: "✈️"),
            .init(name: "Паром", emoji: "⛴️"),
            .init(name: "Аренда байка", emoji: "🏍️"),
            .init(name: "Аренда велосипеда", emoji: "🚲"),
            .init(name: "Самокат", emoji: "🛴"),
            .init(name: "Каршеринг", emoji: "🚗"),
            .init(name: "Топливо", emoji: "⛽"),
            .init(name: "Другое", emoji: "🚦")
        ],
        "Жильё": [
            .init(name: "Аренда", emoji: "🔑"),
            .init(name: "Коммуналка", emoji: "🧾"),
            .init(name: "Интернет", emoji: "📶"),
            .init(name: "Ремонт и мебель", emoji: "🛋️"),
            .init(name: "Другое", emoji: "🏡")
        ],
        "Здоровье и красота": [
            .init(name: "Аптека", emoji: "💊"),
            .init(name: "Врачи и анализы", emoji: "🩺"),
            .init(name: "Стоматология", emoji: "🦷"),
            .init(name: "Спорт и фитнес", emoji: "🏋️"),
            .init(name: "Красота", emoji: "💅"),
            .init(name: "Массаж и спа", emoji: "💆"),
            .init(name: "Другое", emoji: "🏥")
        ],
        "Покупки": [
            .init(name: "Одежда и обувь", emoji: "👕"),
            .init(name: "Электроника", emoji: "📱"),
            .init(name: "Дом и быт", emoji: "🏠"),
            .init(name: "Косметика", emoji: "💄"),
            .init(name: "Подарки и цветы", emoji: "🎁"),
            .init(name: "Маркетплейсы", emoji: "📦"),
            .init(name: "Благотворительность", emoji: "💝"),
            .init(name: "Другое", emoji: "🛍️")
        ],
        "Подписки и связь": [
            .init(name: "Связь и eSIM", emoji: "📡"),
            .init(name: "VPN", emoji: "🛡️"),
            .init(name: "Нейросети", emoji: "🤖"),
            .init(name: "Музыка и видео", emoji: "🎵"),
            .init(name: "Облако", emoji: "☁️"),
            .init(name: "Другое", emoji: "🧩")
        ],
        "Путешествия": [
            .init(name: "Отели", emoji: "🏨"),
            .init(name: "Экскурсии", emoji: "🗺️"),
            .init(name: "Визы и страховки", emoji: "🛂"),
            .init(name: "Другое", emoji: "🧳")
        ],
        "Развлечения": [
            .init(name: "Кино и концерты", emoji: "🎬"),
            .init(name: "Игры", emoji: "🎮"),
            .init(name: "Клубы и вечеринки", emoji: "🪩"),
            .init(name: "Другое", emoji: "🎉")
        ]
    ]

    /// Список подкатегорий для категории (или nil, если их нет).
    static func subcategories(for category: String?) -> [DefaultSubcategoryDefinition]? {
        guard let category else { return nil }
        return SubcategoryRegistry.shared.subcategories(for: category)
    }

    static func hasSubcategories(_ category: String?) -> Bool {
        subcategories(for: category) != nil
    }

    /// Подкатегория по умолчанию («Другое», либо последняя в списке).
    static func defaultSubcategory(for category: String?) -> String? {
        guard let subs = subcategories(for: category) else { return nil }
        return subs.first(where: { $0.name == defaultName })?.name ?? subs.last?.name
    }
}
