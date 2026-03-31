import Foundation
import SwiftData

@Model
final class Transaction {
    var date: Date

    var kindRaw: String

    /// Что ушло с исходного счета.
    /// Для expense — сумма расхода.
    /// Для income — обычно равна зачисленной сумме.
    /// Для transfer — сумма списания с source account.
    var amount: Double
    var currencyCode: String

    /// Что пришло на целевой счет.
    /// Нужна в первую очередь для transfer между разными валютами.
    /// Для обычного same-currency transfer можно хранить такую же сумму.
    var toAmount: Double?
    var toCurrencyCode: String?

    var details: String

    /// Дополнительная сумма в "внешней" валюте:
    /// например, покупка по карте в VND, а списание в KZT.
    var foreignAmount: Double?
    var foreignCurrencyCode: String?

    var rubAmount: Double?

    var categoryName: String?
    var note: String?

    var fingerprint: String?
    var sourceFileName: String?
    var importedAt: Date?

    var createdAt: Date

    var fromAccount: Account?
    var toAccount: Account?

    init(
        date: Date,
        kindRaw: String,
        amount: Double,
        currencyCode: String,
        toAmount: Double? = nil,
        toCurrencyCode: String? = nil,
        details: String,
        foreignAmount: Double? = nil,
        foreignCurrencyCode: String? = nil,
        rubAmount: Double? = nil,
        categoryName: String? = nil,
        note: String? = nil,
        fingerprint: String? = nil,
        sourceFileName: String? = nil,
        importedAt: Date? = nil,
        createdAt: Date = Date(),
        fromAccount: Account? = nil,
        toAccount: Account? = nil
    ) {
        self.date = date
        self.kindRaw = kindRaw
        self.amount = amount
        self.currencyCode = currencyCode
        self.toAmount = toAmount
        self.toCurrencyCode = toCurrencyCode
        self.details = details
        self.foreignAmount = foreignAmount
        self.foreignCurrencyCode = foreignCurrencyCode
        self.rubAmount = rubAmount
        self.categoryName = categoryName
        self.note = note
        self.fingerprint = fingerprint
        self.sourceFileName = sourceFileName
        self.importedAt = importedAt
        self.createdAt = createdAt
        self.fromAccount = fromAccount
        self.toAccount = toAccount
    }
}

extension Transaction {
    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var countsAsExpenseInAnalytics: Bool {
        kind == .expense
    }

    var countsAsIncomeInAnalytics: Bool {
        kind == .income
    }

    var analyticsAmount: Double {
        switch kind {
        case .expense:
            return amount
        case .income:
            return amount
        case .transfer:
            return 0
        }
    }

    var creditedAmount: Double {
        toAmount ?? amount
    }

    var creditedCurrencyCode: String {
        toCurrencyCode ?? currencyCode
    }

    var isCrossCurrencyTransfer: Bool {
        kind == .transfer && creditedCurrencyCode != currencyCode
    }
}

enum TransactionKind: String, CaseIterable, Identifiable {
    case expense
    case income
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: return "Расход"
        case .income: return "Доход"
        case .transfer: return "Перевод"
        }
    }

    var systemImage: String {
        switch self {
        case .expense: return "arrow.up.circle.fill"
        case .income: return "arrow.down.circle.fill"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        }
    }
}
