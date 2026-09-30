import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext

    @Query
    private var categories: [ExpenseCategoryItem]

    @Query
    private var accounts: [Account]

    var body: some View {
        TabView {
            TransactionsView()
                .tabItem {
                    Label("Транзакции", systemImage: "list.bullet.rectangle")
                }
            
            
            AccountsView()
                .tabItem {
                    Label("Счета", systemImage: "wallet.bifold")
                }
            
//            ContentView()
//                .tabItem {
//                    Label("Операции", systemImage: "list.bullet.rectangle")
//                }

            AnalyticsView()
                .tabItem {
                    Label("Аналитика", systemImage: "chart.bar")
                }

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
        }
        .onAppear {
            CategorySeeder.seedIfNeeded(existing: categories, modelContext: modelContext)
            DefaultAccountsSeeder.seedIfNeeded(existingAccounts: accounts, modelContext: modelContext)
            // Убирает дубли, накопившиеся до автоочистки (например, от старого импорта).
            DuplicateCleaner.autoCleanupIfEnabled(context: modelContext)
            ExchangeRateDifferenceCategorySync.run(context: modelContext)
        }
    }
}
