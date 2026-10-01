import SwiftUI
import SwiftData

@main
struct FinancesApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: [
            Expense.self,
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
        ])
    }
}
