import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TransactionsView: View {
    /// PDF из «Поделиться» — импортируется сразу, без выбора файла.
    @Binding var sharedStatementURL: URL?

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @Query(sort: \Account.createdAt, order: .forward)
    private var accounts: [Account]

    @Query(sort: \CategoryRule.priority, order: .reverse)
    private var categoryRules: [CategoryRule]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query
    private var settingsList: [AppSettings]

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @State private var path = NavigationPath()

    @State private var selectedFilter: TransactionKindFilter = .all
    @State private var searchText: String = ""
    @State private var isShowingAddTransaction = false
    @State private var isShowingImporter = false
    /// Доля прочитанных страниц PDF; `nil` — импорт не идёт.
    @State private var importProgress: Double?
    @State private var isShowingQuickTag = false

    @State private var importErrorMessage: String?
    @State private var importResultMessage: String?
    /// Метка последнего импорта — для кнопки «Отменить импорт» в итоговом алерте.
    @State private var lastImportedAt: Date?
    @State private var undoResultMessage: String?
    /// Сверка с «Доступно на …» после последнего импорта — для кнопки «Выровнять баланс».
    @State private var lastBalanceCheck: BalanceCheck?

    private var settings: AppSettings? {
        settingsList.first
    }

    /// Переход из сводки в аналитику месяца.
    private struct MonthAnalyticsRoute: Hashable {
        let month: Date
    }

    /// Курсовые разницы, приписанные к своим покупкам: отдельной строкой не показываются.
    /// Считаются по всем операциям, чтобы пары не зависели от фильтра и поиска.
    private var foldedDifferences: FoldedExchangeRateDifferences {
        ExchangeRateDifferenceMatcher.fold(transactions)
    }

    private func filteredTransactions(folded: FoldedExchangeRateDifferences) -> [Transaction] {
        let hidden = folded.foldedIDs
        let query = searchQuery
        return transactions.filter { transaction in
            !hidden.contains(transaction.persistentModelID)
                && selectedFilter.matches(transaction)
                && matchesSearch(transaction, query: query)
        }
    }

    var body: some View {
        let folded = foldedDifferences
        let visible = filteredTransactions(folded: folded)

        NavigationStack(path: $path) {
            List {
                Section {
                    // При поиске сводка не нужна — на экране только найденное.
                    if searchQuery == nil {
                        monthSummary
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    CapsuleTabs(
                        options: TransactionKindFilter.allCases,
                        selection: $selectedFilter,
                        fillsWidth: true,
                        title: \.rawValue
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if visible.isEmpty {
                    Section {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    TransactionDaySections(
                        transactions: visible,
                        folded: folded,
                        filter: selectedFilter,
                        linkStyle: .value,
                        onDelete: deleteTransaction
                    )
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .navigationTitle("Транзакции")
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let transaction = transactions.first(where: { $0.persistentModelID == id }) {
                    TransactionDetailView(transaction: transaction)
                } else {
                    Text("Транзакция не найдена")
                }
            }
            .navigationDestination(for: MonthAnalyticsRoute.self) { route in
                AnalyticsView(month: route.month)
            }
            .searchable(text: $searchText, prompt: "Поиск по деталям, категории, счетам")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isShowingImporter = true
                        } label: {
                            Label("Импорт выписки PDF", systemImage: "doc.badge.plus")
                        }
                        .disabled(importProgress != nil)

                        Button {
                            isShowingQuickTag = true
                        } label: {
                            Label("Добавить метку", systemImage: "tag")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Ещё")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddTransaction = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Добавить транзакцию")
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
            .onChange(of: sharedStatementURL, initial: true) { _, url in
                guard let url else { return }
                sharedStatementURL = nil
                importSharedStatement(from: url)
            }
            .overlay {
                if let importProgress {
                    importProgressView(importProgress)
                }
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

                if let lastBalanceCheck, !lastBalanceCheck.isMatching {
                    Button("Выровнять баланс") {
                        alignBalance(lastBalanceCheck)
                    }
                }

                if let lastImportedAt {
                    Button("Отменить импорт", role: .destructive) {
                        undoImport(importedAt: lastImportedAt)
                    }
                }
            } message: {
                Text(importResultMessage ?? "")
            }
            .alert("Импорт отменён", isPresented: Binding(
                get: { undoResultMessage != nil },
                set: { if !$0 { undoResultMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    undoResultMessage = nil
                }
            } message: {
                Text(undoResultMessage ?? "")
            }
        }
    }

    /// Сводка текущего месяца; касание открывает его аналитику.
    private var monthSummary: some View {
        let now = Date.now
        let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        let current = monthSnapshot(anchor: now)

        return Button {
            path.append(MonthAnalyticsRoute(month: current.page.startDate))
        } label: {
            TransactionsMonthSummary(
                current: current,
                previous: monthSnapshot(anchor: previousMonth)
            )
        }
        .buttonStyle(.plain)
    }

    private func monthSnapshot(anchor: Date) -> AnalyticsSnapshot {
        AnalyticsSnapshotBuilder.build(
            transactions: transactions,
            scale: .month,
            anchorDate: anchor,
            settings: settings,
            trackedRates: trackedRates
        )
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

    /// Запрос в нижнем регистре; nil — поиск пуст.
    private var searchQuery: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private func matchesSearch(_ transaction: Transaction, query: String?) -> Bool {
        guard let query else { return true }

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

            startImport(from: url)
        }
    }

    /// Файл из «Поделиться»: iOS кладёт его копию в tmp/<bundle id>-Inbox
    /// (на старых версиях — в Documents/Inbox), после импорта она не нужна.
    private func importSharedStatement(from url: URL) {
        let path = url.resolvingSymlinksInPath().path
        let isInboxCopy = [URL.temporaryDirectory, URL.documentsDirectory.appending(path: "Inbox")]
            .map { $0.resolvingSymlinksInPath().path + "/" }
            .contains { path.hasPrefix($0) }
        let removeCopy = {
            if isInboxCopy {
                try? FileManager.default.removeItem(at: url)
            }
        }

        guard importProgress == nil else {
            removeCopy()
            importErrorMessage = "Дождись окончания текущего импорта и отправь выписку ещё раз."
            return
        }

        // Открытые поверх списка окна закрываются — иначе итог импорта не покажется.
        isShowingAddTransaction = false
        isShowingQuickTag = false

        startImport(from: url, onFinish: removeCopy)
    }

    private func startImport(from url: URL, onFinish: @escaping () -> Void = {}) {
        importProgress = 0

        Task {
            defer {
                importProgress = nil
                onFinish()
            }

            do {
                let statement = try await readStatementInBackground(from: url)
                finishImport(statement, fileName: url.lastPathComponent)
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    /// Чтение PDF — самая долгая часть импорта, поэтому она идёт вне главного потока,
    /// а прогресс по страницам приходит через поток значений.
    private func readStatementInBackground(from url: URL) async throws -> KaspiStatement {
        let (progress, continuation) = AsyncStream.makeStream(of: Double.self)

        let reading = Task.detached(priority: .userInitiated) {
            defer { continuation.finish() }
            return try PDFImporter.readStatement(from: url) { continuation.yield($0) }
        }

        for await value in progress {
            importProgress = value
        }

        return try await reading.value
    }

    private func finishImport(_ statement: KaspiStatement, fileName: String) {
        do {
            let importResult = try PDFImporter.importStatement(
                statement,
                fileName: fileName,
                existingTransactions: transactions,
                accounts: accounts,
                rules: categoryRules,
                categories: categories,
                rubRates: RubRateTable.load(context: modelContext)
            )

            for account in importResult.accountsToCreate {
                modelContext.insert(account)
            }

            for transaction in importResult.transactions {
                modelContext.insert(transaction)
            }

            // Оплаты из Apple Pay, найденные в выписке, заменяются её строками.
            let replacedWalletPayments = ApplePayExpenses.replaceWithStatement(
                importResult.walletConfirmations,
                context: modelContext
            )

            // Метки, в даты которых попали операции, — как и у добавленных вручную.
            TransactionTagSync.applyPeriodTags(to: importResult.transactions, context: modelContext)

            try modelContext.save()

            // Курсы на даты из выписки, которых ещё нет, — догрузятся и пересчитают рубли.
            Task { await ExchangeRateSync.shared.run(context: modelContext) }

            let removedDuplicates = DuplicateCleaner.autoCleanupIfEnabled(context: modelContext)

            ImportHistory.add(ImportRecord(
                importedAt: importResult.importedAt,
                fileName: importResult.fileName,
                createdAccountKeys: importResult.accountsToCreate.map(ImportHistory.key(of:)),
                modifications: importResult.modifications,
                removedDuplicateIDs: removedDuplicates.map(\.id),
                replacedWalletPayments: replacedWalletPayments
            ))

            lastImportedAt = importResult.importedAt
            lastBalanceCheck = balanceCheck(for: statement)

            var message = importResult.summaryMessage
            if !removedDuplicates.isEmpty {
                message += "\nУдалено старых дублей: \(removedDuplicates.count)."
            }
            if let lastBalanceCheck {
                message += "\n\n" + lastBalanceCheck.message
            }
            importResultMessage = message

            // Что не распознали правила и словарь — угадает нейросеть, в фоне.
            Task {
                await AICategorizer.runIfEnabled(context: modelContext)
            }
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func importProgressView(_ progress: Double) -> some View {
        VStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 180)

            Text(progress < 1 ? "Читаю выписку… \(Int(progress * 100))%" : "Сверяю с базой…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func balanceCheck(for statement: KaspiStatement) -> BalanceCheck? {
        guard let kaspi = AccountLookup.kaspi(in: accounts),
              let current = try? modelContext.fetch(FetchDescriptor<Transaction>()) else { return nil }
        return BalanceReconciliation.check(statement: statement, transactions: current, kaspi: kaspi)
    }

    private func alignBalance(_ check: BalanceCheck) {
        importResultMessage = nil
        lastBalanceCheck = nil

        guard let kaspi = AccountLookup.kaspi(in: accounts) else { return }

        do {
            try BalanceReconciliation.align(check, kaspi: kaspi, context: modelContext)
        } catch {
            modelContext.rollback()
            importErrorMessage = error.localizedDescription
        }
    }

    private func undoImport(importedAt: Date) {
        importResultMessage = nil
        lastImportedAt = nil
        lastBalanceCheck = nil

        do {
            undoResultMessage = try ImportHistory.undo(importedAt: importedAt, context: modelContext).message
        } catch {
            modelContext.rollback()
            importErrorMessage = error.localizedDescription
        }
    }
}
