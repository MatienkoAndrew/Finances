import Foundation
import SwiftData

enum ExpenseCategory: String, Codable, CaseIterable {
    case food
    case coffee
    case groceries
    case transport
    case subscription
    case shopping
    case cashWithdrawal
    case transfer
    case housing
    case travel
    case health
    case other

    var title: String {
        switch self {
        case .food: return "Еда"
        case .coffee: return "Кофе"
        case .groceries: return "Продукты"
        case .transport: return "Транспорт"
        case .subscription: return "Подписки"
        case .shopping: return "Покупки"
        case .cashWithdrawal: return "Снятие наличных"
        case .transfer: return "Перевод"
        case .housing: return "Жильё"
        case .travel: return "Путешествия"
        case .health: return "Здоровье"
        case .other: return "Другое"
        }
    }
}

@Model
final class Expense {
    var date: Date
    var amount: Double
    var accountCurrency: String
    var operationType: String
    var details: String

    var foreignAmount: Double?
    var foreignCurrency: String?

    var categoryRaw: String?
    var note: String?

    var fingerprint: String?
    var sourceFileName: String?
    var importedAt: Date?

    var createdAt: Date

    var category: ExpenseCategory? {
        get {
            guard let categoryRaw else { return nil }
            return ExpenseCategory(rawValue: categoryRaw)
        }
        set {
            categoryRaw = newValue?.rawValue
        }
    }

    init(
        date: Date,
        amount: Double,
        accountCurrency: String = "₸",
        operationType: String,
        details: String,
        foreignAmount: Double? = nil,
        foreignCurrency: String? = nil,
        category: ExpenseCategory? = nil,
        note: String? = nil,
        fingerprint: String? = nil,
        sourceFileName: String? = nil,
        importedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.date = date
        self.amount = amount
        self.accountCurrency = accountCurrency
        self.operationType = operationType
        self.details = details
        self.foreignAmount = foreignAmount
        self.foreignCurrency = foreignCurrency
        self.categoryRaw = category?.rawValue
        self.note = note
        self.fingerprint = fingerprint
        self.sourceFileName = sourceFileName
        self.importedAt = importedAt
        self.createdAt = createdAt
    }
}
