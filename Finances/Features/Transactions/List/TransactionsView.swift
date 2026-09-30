import SwiftUI
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @Query(sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    @Query(sort: \CategoryRule.priority, order: .reverse)
    private var categoryRules: [CategoryRule]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query(sort: \ExchangeRateEntry.date, order: .reverse)
    private var rates: [ExchangeRateEntry]

    @Query
    private var settingsList: [AppSettings]

    @State private var path = NavigationPath()

    @State private var selectedFilter: TransactionKindFilter = .all
    @State private var searchText: String = ""
    @State private var isShowingAddTransaction = false
    @State private var isShowingImporter = false
    @State private var isShowingQuickTag = false

    @State private var importErrorMessage: String?
    @State private var importResultMessage: String?

    private var settings: AppSettings? {
        settingsList.first
    }

    private var filteredTransactions: [Transaction] {
        transactions.filter { transaction in
            selectedFilter.matches(transaction) && matchesSearch(transaction)
        }
    }

    private var groupedTransactions: [(date: Date, items: [Transaction])] {
        TransactionSectionGrouper.groupedByDay(filteredTransactions)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    filterChips
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                if filteredTransactions.isEmpty {
                    Section {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(groupedTransactions, id: \.date) { section in
                        Section {
                            ForEach(section.items) { transaction in
                                TransactionRowView(transaction: transaction)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        path.append(transaction.persistentModelID)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteTransaction(transaction)
                                        } label: {
                                            Label("Удалить", systemImage: "trash")
                                        }
                                    }
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                        } header: {
                            HStack {
                                Text(formattedSectionDate(section.date))
                                    .font(.title3.weight(.semibold))
                                    .textCase(nil)
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                if let (totalText, color) = calculateDailyTotal(section.items) {
                                    Text(totalText)
                                        .font(.subheadline.weight(.semibold))
                                        .textCase(nil)
                                        .foregroundStyle(color)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            color.opacity(0.15),
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                }
                            }
                            .padding(.bottom, 4)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Транзакции")
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let transaction = transactions.first(where: { $0.persistentModelID == id }) {
                    TransactionDetailView(transaction: transaction)
                } else {
                    Text("Транзакция не найдена")
                }
            }
            .searchable(text: $searchText, prompt: "Поиск по деталям, категории, счетам")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingQuickTag = true
                    } label: {
                        Image(systemName: "tag.fill")
                    }
                    
                    Button {
                        isShowingImporter = true
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }

                    Button {
                        isShowingAddTransaction = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddTransaction) {
                AddTransactionView()
            }
            .sheet(isPresented: $isShowingQuickTag) {
                QuickTagView()
            }
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: [.item],
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
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TransactionKindFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedFilter == filter
                                ? Color.primary.opacity(0.10)
                                : Color(.secondarySystemBackground)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text(emptyTitle)
                .font(.headline)

            Text(emptySubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Добавить транзакцию") {
                isShowingAddTransaction = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyTitle: String {
        searchText.isEmpty ? "Пока нет транзакций" : "Ничего не найдено"
    }

    private var emptySubtitle: String {
        if !searchText.isEmpty {
            return "Попробуй изменить запрос или фильтр"
        }

        switch selectedFilter {
        case .all:
            return "Добавь первую транзакцию или импортируй PDF из Kaspi"
        case .expenses:
            return "Пока нет расходов"
        case .income:
            return "Пока нет доходов"
        case .transfers:
            return "Пока нет переводов"
        }
    }

    private func deleteTransaction(_ transaction: Transaction) {
        modelContext.delete(transaction)
        try? modelContext.save()
    }

    private func matchesSearch(_ transaction: Transaction) -> Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let query = trimmed.lowercased()

        let haystack = [
            transaction.details,
            transaction.categoryName ?? "",
            transaction.note ?? "",
            transaction.fromAccount?.name ?? "",
            transaction.toAccount?.name ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        return haystack.contains(query)
    }

    private func formattedSectionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }
    
    /// Подсчет суммы за день в рублях с учетом фильтра
    private func calculateDailyTotal(_ transactions: [Transaction]) -> (String, Color)? {
        var totalRub: Double = 0
        
        // Подсчитываем сумму в зависимости от выбранного фильтра
        switch selectedFilter {
        case .all:
            // Показываем чистый баланс: доходы минус расходы
            let expenses = transactions.filter { $0.kind == .expense }
                .reduce(0.0) { sum, tx in sum + (tx.rubAmount ?? 0) }
            
            let income = transactions.filter { $0.kind == .income }
                .reduce(0.0) { sum, tx in sum + (tx.rubAmount ?? 0) }
            
            totalRub = income - expenses
            
        case .expenses:
            // Только расходы (делаем отрицательными)
            totalRub = -transactions.filter { $0.kind == .expense }
                .reduce(0.0) { sum, tx in sum + (tx.rubAmount ?? 0) }
            
        case .income:
            // Только доходы (положительные)
            totalRub = transactions.filter { $0.kind == .income }
                .reduce(0.0) { sum, tx in sum + (tx.rubAmount ?? 0) }
            
        case .transfers:
            // Для переводов не показываем сумму
            return nil
        }
        
        guard totalRub != 0 else { return nil }
        
        // Определяем цвет и формат в зависимости от типа операций и суммы
        if selectedFilter == .all {
            // Для "Все": зеленый если положительный, красный если отрицательный
            let color: Color = totalRub > 0 ? .green : .red
            return (signedFormattedRubAmount(totalRub), color)
        } else if selectedFilter == .expenses {
            // Для расходов: всегда красный цвет и со знаком минус
            return (signedFormattedRubAmount(totalRub), .red)
        } else if selectedFilter == .income {
            // Для доходов: всегда зеленый цвет и со знаком плюс
            return (signedFormattedRubAmount(totalRub), .green)
        }
        
        return nil
    }
    
    /// Форматирование суммы в рублях
    private func formattedRubAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","
        
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) ₽"
    }
    
    /// Форматирование суммы в рублях со знаком
    private func signedFormattedRubAmount(_ value: Double) -> String {
        let sign = value < 0 ? "-" : "+"
        return "\(sign) \(formattedRubAmount(abs(value)))"
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importErrorMessage = error.localizedDescription

        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.pathExtension.lowercased() == "pdf" else {
                importErrorMessage = "Выбери PDF-файл."
                return
            }

            do {
                let importResult = try PDFImporter.importTransactions(
                    from: url,
                    existingTransactions: transactions,
                    accounts: accounts,
                    rules: categoryRules,
                    categories: categories,
                    rates: rates,
                    fallbackKztPerRub: settings?.kztPerRub
                )

                for account in importResult.accountsToCreate {
                    modelContext.insert(account)
                }

                for transaction in importResult.transactions {
                    modelContext.insert(transaction)
                }

                try modelContext.save()

                let removedDuplicates = DuplicateCleaner.autoCleanupIfEnabled(context: modelContext)
                importResultMessage = importResult.summaryMessage
                    + (removedDuplicates > 0 ? "\nУдалено старых дублей: \(removedDuplicates)." : "")
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }
}
