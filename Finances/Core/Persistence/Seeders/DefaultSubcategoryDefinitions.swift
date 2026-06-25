//
//  DefaultSubcategoryDefinitions.swift
//  Finances
//
//  Подкатегории внутри основных категорий. Пока заполнена только «Еда».
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

    static let byCategory: [String: [DefaultSubcategoryDefinition]] = [
        "Еда": [
            .init(name: "Кафе", emoji: "☕️"),
            .init(name: "Супермаркет", emoji: "🛒"),
            .init(name: "Ресторан", emoji: "🍽️"),
            .init(name: "Доставка", emoji: "🛵"),
            .init(name: "Фастфуд", emoji: "🍔"),
            .init(name: "Бар", emoji: "🍺"),
            .init(name: "Другое", emoji: "🍴")
        ],
        "Транспорт": [
            .init(name: "Такси", emoji: "🚕"),
            .init(name: "Общественный транспорт", emoji: "🚌"),
            .init(name: "Аренда велосипеда", emoji: "🚲"),
            .init(name: "Аренда байка", emoji: "🏍️"),
            .init(name: "Каршеринг", emoji: "🚗"),
            .init(name: "Заправка", emoji: "⛽"),
            .init(name: "Парковка", emoji: "🅿️"),
            .init(name: "Платные дороги", emoji: "🛣️"),
            .init(name: "Самокат", emoji: "🛴"),
            .init(name: "Поезд/электричка", emoji: "🚆"),
            .init(name: "Другое", emoji: "🚦")
        ],
        "Подписки": [
            .init(name: "Музыка", emoji: "🎵"),
            .init(name: "Облако", emoji: "☁️"),
            .init(name: "Связь", emoji: "📱"),
            .init(name: "ИИ", emoji: "🤖"),
            .init(name: "Другое", emoji: "🧩")
        ],
        "Покупки": [
            .init(name: "Одежда", emoji: "👕"),
            .init(name: "Обувь", emoji: "👟"),
            .init(name: "Электроника", emoji: "📱"),
            .init(name: "Дом/быт", emoji: "🏠"),
            .init(name: "Косметика", emoji: "💄"),
            .init(name: "Подарки", emoji: "🎁"),
            .init(name: "Маркетплейсы", emoji: "📦"),
            .init(name: "Другое", emoji: "🛍️")
        ],
        "Жильё": [
            .init(name: "Аренда", emoji: "🔑"),
            .init(name: "Ипотека", emoji: "🏦"),
            .init(name: "Коммуналка", emoji: "🧾"),
            .init(name: "Интернет", emoji: "📶"),
            .init(name: "Ремонт", emoji: "🔨"),
            .init(name: "Мебель/техника", emoji: "🛋️"),
            .init(name: "Другое", emoji: "🏡")
        ],
        "Путешествия": [
            .init(name: "Авиабилеты", emoji: "🛫"),
            .init(name: "Отели", emoji: "🏨"),
            .init(name: "Ж/д билеты", emoji: "🚆"),
            .init(name: "Аренда авто", emoji: "🚗"),
            .init(name: "Экскурсии", emoji: "🗺️"),
            .init(name: "Виза/страховка", emoji: "🛂"),
            .init(name: "Другое", emoji: "✈️")
        ],
        "Здоровье": [
            .init(name: "Аптека", emoji: "💊"),
            .init(name: "Врач/клиника", emoji: "🩺"),
            .init(name: "Анализы", emoji: "🧪"),
            .init(name: "Стоматология", emoji: "🦷"),
            .init(name: "Спорт/фитнес", emoji: "🏋️"),
            .init(name: "Косметолог", emoji: "💆"),
            .init(name: "Другое", emoji: "🏥")
        ]
    ]

    /// Список подкатегорий для категории (или nil, если их нет).
    static func subcategories(for category: String?) -> [DefaultSubcategoryDefinition]? {
        guard let category else { return nil }
        return byCategory[category]
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
