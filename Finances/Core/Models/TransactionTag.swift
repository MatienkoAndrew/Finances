import Foundation
import SwiftData

/// Метка для группировки транзакций (например, по странам, проектам, поездкам)
@Model
final class TransactionTag {
    var name: String
    var startDate: Date?
    var endDate: Date?
    var icon: String? // SF Symbol или emoji
    var colorHex: String?
    var createdAt: Date

    /// ISO-код валюты для авто-применения метки (например, "HKD" для Гонконга).
    /// Если задан, метка автоматически навешивается на любые транзакции, у которых
    /// валюта мерчанта (`foreignCurrencyCode ?? currencyCode`) совпадает с этим кодом.
    /// Optional, чтобы старые TransactionTag не сломались при миграции SwiftData.
    var autoCurrencyCode: String?

    init(
        name: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        icon: String? = nil,
        colorHex: String? = nil,
        createdAt: Date = Date(),
        autoCurrencyCode: String? = nil
    ) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.autoCurrencyCode = autoCurrencyCode
    }
}

extension TransactionTag {
    /// Проверяет, попадает ли дата в период метки
    func contains(date: Date) -> Bool {
        guard let start = startDate, let end = endDate else {
            return false
        }
        return date >= start && date <= end
    }
    
    /// Отображаемая строка периода
    var periodDescription: String {
        guard let start = startDate, let end = endDate else {
            return "Без периода"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
    
    /// Иконка с фоллбэком
    var displayIcon: String {
        icon ?? "tag.fill"
    }
}
