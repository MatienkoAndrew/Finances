import Foundation
import SwiftData

@Model
final class TrackedExchangeRate {
    var code: String
    var displayName: String
    var flag: String
    /// Сколько RUB за 1 единицу валюты
    var rubPerUnit: Double
    var createdAt: Date

    init(
        code: String,
        displayName: String,
        flag: String,
        rubPerUnit: Double,
        createdAt: Date = Date()
    ) {
        self.code = code.uppercased()
        self.displayName = displayName
        self.flag = flag
        self.rubPerUnit = rubPerUnit
        self.createdAt = createdAt
    }
}
