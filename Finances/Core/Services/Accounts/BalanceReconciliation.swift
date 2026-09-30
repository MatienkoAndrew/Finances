import Foundation
import SwiftData

/// Сравнение остатка Kaspi в приложении с «Доступно на …» из выписки.
struct BalanceCheck {
    /// Конец периода выписки.
    let date: Date
    let statementBalance: Double
    let appBalance: Double

    /// Сколько не хватает в приложении до остатка по выписке.
    var difference: Double { statementBalance - appBalance }

    var isMatching: Bool { abs(difference) < 0.005 }

    var message: String {
        let day = date.formatted(date: .numeric, time: .omitted)
        if isMatching {
            return "Баланс Kaspi на \(day) сходится с выпиской: \(Self.format(statementBalance)) ✓"
        }
        return "Баланс Kaspi на \(day): в выписке \(Self.format(statementBalance)), в приложении \(Self.format(appBalance)). "
            + "Если до этой выписки на счету уже были деньги — нажми «Выровнять баланс». "
            + "Небольшая разница бывает из-за сумм, которые банк ещё держит заблокированными."
    }

    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","
        return "\(formatter.string(from: NSNumber(value: value)) ?? "\(value)") ₸"
    }
}

/// Сверка баланса Kaspi с выпиской.
///
/// У счёта нет начального остатка: баланс — это сумма операций. Если импорт начался
/// не с открытия счёта, баланс в приложении всегда меньше на сумму, что была на счету
/// до первой выписки. «Выровнять» заводит одну операцию «Начальный остаток» — перевод
/// извне на Kaspi перед самой ранней операцией (в аналитику переводы не попадают).
/// После этого расхождение в следующих выписках — сигнал, что чего-то не хватает.
enum BalanceReconciliation {
    static let adjustmentDetails = "Начальный остаток Kaspi"

    static func check(statement: KaspiStatement, transactions: [Transaction], kaspi: Account) -> BalanceCheck? {
        guard let periodEnd = statement.periodEnd,
              let statementBalance = statement.closingBalance else { return nil }

        let calendar = KaspiStatementParser.calendar
        guard let cutoff = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: periodEnd)) else { return nil }

        let appBalance = AccountBalanceCalculator.balance(
            for: kaspi,
            transactions: transactions.filter { $0.date < cutoff }
        )

        return BalanceCheck(
            date: periodEnd,
            statementBalance: (statementBalance * 100).rounded() / 100,
            appBalance: (appBalance * 100).rounded() / 100
        )
    }

    /// Доводит начальный остаток так, чтобы баланс на дату сверки совпал с выпиской.
    static func align(_ check: BalanceCheck, kaspi: Account, context: ModelContext) throws {
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let kaspiID = kaspi.persistentModelID

        func touchesKaspi(_ transaction: Transaction) -> Bool {
            transaction.fromAccount?.persistentModelID == kaspiID || transaction.toAccount?.persistentModelID == kaspiID
        }

        let existing = transactions.first { $0.kind == .transfer && $0.details == adjustmentDetails && touchesKaspi($0) }
        let currentValue = existing.map { $0.toAccount?.persistentModelID == kaspiID ? $0.amount : -$0.amount } ?? 0
        let newValue = ((currentValue + check.difference) * 100).rounded() / 100

        let adjustment: Transaction
        if let existing {
            adjustment = existing
        } else {
            let earliest = transactions.filter { touchesKaspi($0) }.map(\.date).min() ?? check.date
            let calendar = KaspiStatementParser.calendar
            let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: earliest)) ?? earliest
            adjustment = Transaction(
                date: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayBefore) ?? dayBefore,
                kindRaw: TransactionKind.transfer.rawValue,
                amount: 0,
                currencyCode: "KZT",
                details: adjustmentDetails,
                note: "Выровнено по выписке Kaspi"
            )
            context.insert(adjustment)
        }

        if abs(newValue) < 0.005 {
            context.delete(adjustment)
        } else {
            adjustment.amount = abs(newValue)
            adjustment.toAmount = nil
            adjustment.fromAccount = newValue < 0 ? kaspi : nil
            adjustment.toAccount = newValue > 0 ? kaspi : nil
        }

        try context.save()
    }
}
