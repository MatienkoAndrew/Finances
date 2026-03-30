import Foundation
import SwiftData

@Model
final class Expense {
    var date: Date
    var amount: Double
    var accountCurrency: String
    var operationType: String
    var details: String

    var foreignAmount: Double?
    var foreignCurrency: String?
    var rubAmount: Double?

    var categoryName: String?
    var note: String?

    var fingerprint: String?
    var sourceFileName: String?
    var importedAt: Date?

    var createdAt: Date

    init(
        date: Date,
        amount: Double,
        accountCurrency: String = "₸",
        operationType: String,
        details: String,
        foreignAmount: Double? = nil,
        foreignCurrency: String? = nil,
        rubAmount: Double? = nil,
        categoryName: String? = nil,
        note: String? = nil,
        fingerprint: String? = nil,
        sourceFileName: String? = nil,
        importedAt: Date? = nil,
        createdAt: Date = Date(),
    ) {
        self.date = date
        self.amount = amount
        self.accountCurrency = accountCurrency
        self.operationType = operationType
        self.details = details
        self.foreignAmount = foreignAmount
        self.foreignCurrency = foreignCurrency
        self.rubAmount = rubAmount
        self.categoryName = categoryName
        self.note = note
        self.fingerprint = fingerprint
        self.sourceFileName = sourceFileName
        self.importedAt = importedAt
        self.createdAt = createdAt
    }
}
