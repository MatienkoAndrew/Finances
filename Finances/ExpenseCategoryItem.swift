//
//  ExpenseCategoryItem.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import Foundation
import SwiftData

@Model
final class ExpenseCategoryItem {
    var name: String
    var isSystem: Bool
    var createdAt: Date

    init(
        name: String,
        isSystem: Bool = false,
        createdAt: Date = Date()
    ) {
        self.name = name
        self.isSystem = isSystem
        self.createdAt = createdAt
    }
}