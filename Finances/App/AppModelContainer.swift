import SwiftData

/// Одна база на всё приложение. Её используют и экраны, и действие для «Команд»,
/// которое iOS запускает в фоне без интерфейса: так трата из Apple Pay сразу
/// появляется в открытых списках.
enum AppModelContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(
                for: Expense.self,
                CategoryRule.self,
                AppSettings.self,
                ExpenseCategoryItem.self,
                ExpenseSubcategoryItem.self,
                ExchangeRateEntry.self,
                DailyExchangeRate.self,
                TrackedExchangeRate.self,
                Account.self,
                Transaction.self,
                TransactionTag.self
            )
        } catch {
            fatalError("Не удалось открыть базу данных: \(error)")
        }
    }()
}
