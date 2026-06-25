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
            .init(name: "Кофе", emoji: "☕️"),
            .init(name: "Супермаркеты", emoji: "🛒"),
            .init(name: "Другое", emoji: "🍽️")
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
