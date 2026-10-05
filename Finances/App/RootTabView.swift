import SwiftUI
import SwiftData

struct RootTabView: View {
    private enum RootTab: Hashable {
        case transactions, accounts, analytics, settings
    }

    @Environment(\.modelContext) private var modelContext

    @Query
    private var categories: [ExpenseCategoryItem]

    @Query
    private var accounts: [Account]

    @State private var selectedTab: RootTab = .transactions
    /// PDF, отправленный в приложение через «Поделиться» (например, выписка из Kaspi).
    @State private var sharedStatementURL: URL?

    var body: some View {
        TabView(selection: $selectedTab) {
            TransactionsView(sharedStatementURL: $sharedStatementURL)
                .tabItem {
                    Label("Транзакции", systemImage: "list.bullet.rectangle")
                }
                .tag(RootTab.transactions)
            
            
            AccountsView()
                .tabItem {
                    Label("Счета", systemImage: "wallet.bifold")
                }
                .tag(RootTab.accounts)
            
//            ContentView()
//                .tabItem {
//                    Label("Операции", systemImage: "list.bullet.rectangle")
//                }

            AnalyticsView()
                .tabItem {
                    Label("Аналитика", systemImage: "chart.bar")
                }
                .tag(RootTab.analytics)

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
                .tag(RootTab.settings)
        }
        .onOpenURL { url in
            // Импорт и его итог показывает экран транзакций.
            guard url.isFileURL else { return }
            selectedTab = .transactions
            sharedStatementURL = url
        }
        .onAppear {
            CategorySeeder.seedIfNeeded(existing: categories, modelContext: modelContext)
            CategoryStructureMigration.runIfNeeded(context: modelContext)
            SubcategoryRegistry.shared.load(context: modelContext)
            DefaultAccountsSeeder.seedIfNeeded(existingAccounts: accounts, modelContext: modelContext)
            // Убирает дубли, накопившиеся до автоочистки (например, от старого импорта).
            DuplicateCleaner.autoCleanupIfEnabled(context: modelContext)
            // «Другое» и пустые категории — по правилам, истории выбора и словарю мерчантов.
            AutoCategorizationSync.run(context: modelContext)
            ExchangeRateDifferenceCategorySync.run(context: modelContext)
            // Копии меток с одинаковым именем (например, от двойного касания).
            TransactionTagSync.removeDuplicates(context: modelContext)
        }
        .task {
            // Курсы ЦБ по дням и ₽-эквивалент операций по курсу на их дату.
            await ExchangeRateSync.shared.run(context: modelContext)
        }
        .task {
            // Оставшееся «Другое» — нейросеть на устройстве, в фоне.
            await AICategorizer.runIfEnabled(context: modelContext)
        }
    }
}
