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

    /// Раньше по этому коду валюты метка ставилась сама (например, "HKD" → Гонконг).
    /// Больше не используется: метки ставятся по датам периода. Поле осталось,
    /// чтобы не ломать сохранённые данные и резервные копии.
    var autoCurrencyCode: String?

    /// Валюты поездки (JPY для Японии). Если заданы, за даты периода метку сами
    /// получают только операции в этих валютах, а остальные расходы ждут решения.
    /// nil — метка ставится на все операции за даты. Optional — для миграции.
    var currencyCodes: [String]?

    init(
        name: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        icon: String? = nil,
        colorHex: String? = nil,
        createdAt: Date = Date(),
        autoCurrencyCode: String? = nil,
        currencyCodes: [String]? = nil
    ) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.autoCurrencyCode = autoCurrencyCode
        self.currencyCodes = currencyCodes
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
    
    /// Валюты поездки в едином виде (KZT, JPY); пусто — метка только по датам.
    var tripCurrencyCodes: Set<String> {
        Set((currencyCodes ?? []).map { CurrencyDisplay.normalizedCode(from: $0) })
    }

    /// Иконка с фоллбэком
    var displayIcon: String {
        icon ?? "tag.fill"
    }
}
