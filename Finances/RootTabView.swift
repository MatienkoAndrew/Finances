import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext

    @Query
    private var categories: [ExpenseCategoryItem]

    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Операции", systemImage: "list.bullet.rectangle")
                }

            AnalyticsView()
                .tabItem {
                    Label("Аналитика", systemImage: "chart.bar")
                }

            RulesView()
                .tabItem {
                    Label("Правила", systemImage: "wand.and.stars")
                }

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
        }
        .onAppear {
            CategorySeeder.seedIfNeeded(existing: categories, modelContext: modelContext)
        }
    }
}
