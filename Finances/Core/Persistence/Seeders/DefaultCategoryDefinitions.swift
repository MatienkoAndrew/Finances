//
//  DefaultCategoryDefinition.swift
//  Finances
//
//  Created by Андрей Матиенко on 21.03.2026.
//


import Foundation

struct DefaultCategoryDefinition {
    let name: String
    let iconName: String
    let colorHex: String
}

enum DefaultCategoryDefinitions {
    static let items: [DefaultCategoryDefinition] = [
        .init(name: "Еда", iconName: "fork.knife", colorHex: "#FF9500"),
        .init(name: "Продукты", iconName: "cart.fill", colorHex: "#34C759"),
        .init(name: "Транспорт", iconName: "car.fill", colorHex: "#007AFF"),
        .init(name: "Подписки", iconName: "creditcard.fill", colorHex: "#AF52DE"),
        .init(name: "Покупки", iconName: "bag.fill", colorHex: "#FF2D55"),
        .init(name: "Снятие наличных", iconName: "banknote.fill", colorHex: "#30B0C7"),
        .init(name: "Перевод", iconName: "arrow.left.arrow.right", colorHex: "#5856D6"),
        .init(name: "Жильё", iconName: "house.fill", colorHex: "#32ADE6"),
        .init(name: "Путешествия", iconName: "airplane", colorHex: "#5AC8FA"),
        .init(name: "Здоровье", iconName: "cross.case.fill", colorHex: "#FF3B30"),
        .init(name: "Другое", iconName: "square.grid.2x2.fill", colorHex: "#8E8E93")
    ]
}