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
            ExchangeRateEntry.self,
            TrackedExchangeRate.self
        ])
    }
}
