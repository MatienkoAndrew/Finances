import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Expense.date, order: .reverse)
    private var expenses: [Expense]

    @State private var isShowingAddExpense = false
    @State private var isShowingImporter = false
    @State private var importErrorMessage: String?
    @State private var importResultMessage: String?

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
                        ForEach(expenses) { expense in
                            ExpenseRowView(expense: expense)
                        }
                        .onDelete(perform: deleteExpenses)
                    }
                }
            }
            .navigationTitle("Операции")
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
            .alert("Ошибка импорта", isPresented: .constant(importErrorMessage != nil)) {
                Button("OK") {
                    importErrorMessage = nil
                }
            } message: {
                Text(importErrorMessage ?? "")
            }
            .alert("Импорт завершен", isPresented: .constant(importResultMessage != nil)) {
                Button("OK") {
                    importResultMessage = nil
                }
            } message: {
                Text(importResultMessage ?? "")
            }
        }
    }

    private func deleteExpenses(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(expenses[index])
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importErrorMessage = error.localizedDescription

        case .success(let urls):
            guard let url = urls.first else { return }

            do {
                let importedExpenses = try PDFImporter.importExpenses(from: url)

                for expense in importedExpenses {
                    modelContext.insert(expense)
                }

                importResultMessage = "Импортировано \(importedExpenses.count) операций"
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }
}
