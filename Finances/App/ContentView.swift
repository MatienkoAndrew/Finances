import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    
    @Query(sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]
    
    private var settings: AppSettings? {
        settingsList.first
    }

    @Query(sort: \Expense.date, order: .reverse)
    private var expenses: [Expense]
    
    @Query(sort: \CategoryRule.priority, order: .reverse)
    private var categoryRules: [CategoryRule]
    
    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]
    
    @Query(sort: \ExchangeRateEntry.date, order: .reverse)
    private var rates: [ExchangeRateEntry]

    @Query
    private var settingsList: [AppSettings]

    @State private var isShowingAddExpense = false
    @State private var isShowingImporter = false

    @State private var importErrorMessage: String?
    @State private var importResultMessage: String?

    @State private var isShowingDeleteAllConfirmation = false
    
    @State private var selectedFilter: ExpenseFilter = .all
    
    @State private var isShowingAutoCategorizeConfirmation = false

    private var filteredExpenses: [Expense] {
        expenses.filter { selectedFilter.matches($0) }
    }

    private var groupedExpenses: [(date: Date, expenses: [Expense])] {
        let grouped = Dictionary(grouping: filteredExpenses) {
            Calendar.current.startOfDay(for: $0.date)
        }

        return grouped
            .map { (date: $0.key, expenses: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if expenses.isEmpty {
                    ContentUnavailableView(
                        "Нет операций",
                        systemImage: "tray",
                        description: Text("Добавь первую операцию вручную или импортируй PDF.")
                    )
                } else {
                    List {
                        ForEach(groupedExpenses, id: \.date) { section in
                            Section {
                                ForEach(section.expenses) { expense in
                                    NavigationLink {
                                        ExpenseDetailView(expense: expense)
                                    } label: {
                                        ExpenseRowView(expense: expense)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowSeparator(.hidden)
                                }
                                .onDelete { offsets in
                                    deleteExpenses(offsets, in: section.expenses)
                                }
                            } header: {
                                Text(section.date, format: .dateTime.day().month().year())
                                    .font(.title3.bold())
                                    .textCase(nil)
                                    .padding(.top, 8)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Операции")
            .safeAreaInset(edge: .top) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ExpenseFilter.allCases, id: \.self) { filter in
                            Button {
                                selectedFilter = filter
                            } label: {
                                Text(filter.rawValue)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedFilter == filter
                                        ? Color.primary.opacity(0.1)
                                        : Color.gray.opacity(0.1)
                                    )
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Операции (\(filteredExpenses.count))")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingImporter = true
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }

                    Button {
                        isShowingAddExpense = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    
                    if !expenses.isEmpty {
                        Button {
                            isShowingAutoCategorizeConfirmation = true
                        } label: {
                            Image(systemName: "wand.and.stars")
                        }
                    }

                    if !expenses.isEmpty {
                        Button(role: .destructive) {
                            isShowingDeleteAllConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingAddExpense) {
                AddExpenseView()
            }
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("Автоматически расставить категории?", isPresented: $isShowingAutoCategorizeConfirmation) {
                Button("Применить") {
                    autoCategorizeExpenses()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Категории будут выставлены только там, где они ещё не указаны вручную.")
            }
            .alert("Ошибка импорта", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    importErrorMessage = nil
                }
            } message: {
                Text(importErrorMessage ?? "")
            }
            .alert("Импорт завершен", isPresented: Binding(
                get: { importResultMessage != nil },
                set: { if !$0 { importResultMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    importResultMessage = nil
                }
            } message: {
                Text(importResultMessage ?? "")
            }
            .alert("Удалить все операции?", isPresented: $isShowingDeleteAllConfirmation) {
                Button("Удалить все", role: .destructive) {
                    deleteAllExpenses()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Это действие нельзя отменить.")
            }
        }
    }
    
    private func autoCategorizeExpenses() {
        for expense in expenses {
            guard expense.categoryName == nil else { continue }

            let guessed = CategoryRuleEngine.matchCategoryName(
                operationType: expense.operationType,
                details: expense.details,
                rules: categoryRules,
                existingCategories: categories
            )

            if let guessed {
                expense.categoryName = guessed
            }
        }
    }

    private func deleteExpenses(_ offsets: IndexSet, in sectionExpenses: [Expense]) {
        for index in offsets {
            modelContext.delete(sectionExpenses[index])
        }
    }

    private func deleteAllExpenses() {
        for expense in expenses {
            modelContext.delete(expense)
        }
    }
    
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importErrorMessage = error.localizedDescription

        case .success(let urls):
            guard let url = urls.first else { return }

            do {
                let result = try PDFImporter.importTransactions(
                    from: url,
                    existingTransactions: transactions,
                    accounts: accounts,
                    rules: categoryRules,
                    categories: categories,
                    rates: rates,
                    fallbackKztPerRub: settings?.kztPerRub
                )

                for account in result.accountsToCreate {
                    modelContext.insert(account)
                }

                for transaction in result.transactions {
                    modelContext.insert(transaction)
                }

                try modelContext.save()

                importResultMessage = result.summaryMessage
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }

//    private func handleImport(_ result: Result<[URL], Error>) {
//        switch result {
//        case .failure(let error):
//            importErrorMessage = error.localizedDescription
//
//        case .success(let urls):
//            guard let url = urls.first else { return }
//
//            do {
//                let importedTransactions = try PDFImporter.importTransactions(
//                    from: url,
//                    existingTransactions: transactions,
//                    accounts: accounts,
//                    rules: categoryRules,
//                    rates: rates,
//                    fallbackKztPerRub: settings?.kztPerRub
//                )
//
//                for transaction in importedTransactions {
//                    modelContext.insert(transaction)
//                }
//
//                try modelContext.save()
//
//                importResultMessage = "Импортировано \(importedTransactions.count) новых операций"
//            } catch {
//                importErrorMessage = error.localizedDescription
//            }
//        }
//    }
}
