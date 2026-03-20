//
//  AppSettings.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import Foundation
import SwiftData

@Model
final class AppSettings {
    /// Сколько KZT в 1 RUB
    var kztPerRub: Double
    var createdAt: Date

    init(kztPerRub: Double = 5.8, createdAt: Date = Date()) {
        self.kztPerRub = kztPerRub
        self.createdAt = createdAt
    }
}