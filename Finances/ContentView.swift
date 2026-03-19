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

    @State private var isShowingDeleteAllConfirmation = false

    private var groupedExpenses: [(date: Date, expenses: [Expense])] {
        let grouped = Dictionary(grouping: expenses) {
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
                let importedExpenses = try PDFImporter.importExpenses(from: url, existingExpenses: expenses)

                for expense in importedExpenses {
                    modelContext.insert(expense)
                }

                importResultMessage = "Импортировано \(importedExpenses.count) новых операций"
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }
}
