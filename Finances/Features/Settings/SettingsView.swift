import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @Query(sort: \DailyExchangeRate.day, order: .forward)
    private var dailyRates: [DailyExchangeRate]

    @Query
    private var transactions: [Transaction]

    @State private var isShowingAddCurrency = false
    @State private var isExporting = false
    @State private var exportFileURL: URL?
    @State private var isShowingImportPicker = false
    @State private var isShowingImportConfirmation = false
    @State private var selectedImportURL: URL?
    @State private var exportErrorMessage: String?
    @State private var importErrorMessage: String?
    @State private var importSuccessMessage: String?

    private var rateSync: ExchangeRateSync { .shared }

    /// Сколько операций в каждой валюте.
    private var operationCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for transaction in transactions {
            counts[CurrencyDisplay.normalizedCode(from: transaction.currencyCode), default: 0] += 1
        }
        return counts
    }

    /// Сначала валюты, в которых больше всего операций, потом остальные по коду.
    private func displayedTrackedRates(_ counts: [String: Int]) -> [TrackedExchangeRate] {
        trackedRates.sorted { lhs, rhs in
            let left = counts[CurrencyDisplay.normalizedCode(from: lhs.code)] ?? 0
            let right = counts[CurrencyDisplay.normalizedCode(from: rhs.code)] ?? 0
            if left != right { return left > right }
            return lhs.code < rhs.code
        }
    }

    /// Откуда курсы, как считаются рубли и когда обновлялись.
    private var ratesFooter: String {
        if let error = rateSync.lastError { return error }
        var text = "Курсы ЦБ РФ, для валют, которых у ЦБ нет, — открытый currency-api. Рубли у каждой операции считаются по курсу на её дату."
        if let updated = rateSync.lastUpdated {
            text += " Обновлено \(Self.relative(updated))."
        }
        return text
    }

    private static func relative(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "ru_RU")))
        if calendar.isDateInToday(date) { return "сегодня в \(time)" }
        if calendar.isDateInYesterday(date) { return "вчера в \(time)" }
        return "\(date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU")))) в \(time)"
    }

    var body: some View {
        let counts = operationCounts
        let rateTable = RubRateTable(rates: dailyRates)
        let displayedRates = displayedTrackedRates(counts)

        NavigationStack {
            Form {
                Section {
                    ForEach(displayedRates) { rate in
                        let code = CurrencyDisplay.normalizedCode(from: rate.code)
                        CurrencyRateRow(rate: rate, latest: rateTable.latest(code))
                        // Валюты из операций всё равно вернутся в список.
                        .deleteDisabled((counts[code] ?? 0) > 0)
                    }
                    .onDelete { offsets in
                        deleteTrackedRates(offsets.map { displayedRates[$0] })
                    }

                    Button {
                        isShowingAddCurrency = true
                    } label: {
                        Label("Добавить валюту", systemImage: "plus")
                    }

                    Button {
                        Task { await rateSync.run(context: modelContext) }
                    } label: {
                        HStack {
                            Label(rateSync.isRunning ? "Обновляем курсы…" : "Обновить курсы", systemImage: "arrow.clockwise")
                            Spacer()
                            if rateSync.isRunning {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(rateSync.isRunning)
                } header: {
                    Text("Валюты и курсы")
                } footer: {
                    Text(ratesFooter)
                }

                Section("Данные") {
                    NavigationLink("Категории") {
                        CategoriesView()
                    }

                    NavigationLink("Запомненные мерчанты") {
                        LearnedMerchantsView()
                    }

                    AICategorizationRow()
                    
                    NavigationLink("Метки") {
                        TagsManagementView()
                    }

                    NavigationLink("Поиск дублей") {
                        DuplicatesView()
                    }

                    NavigationLink("История импортов") {
                        ImportHistoryView()
                    }
                }
                
                Section("Резервное копирование") {
                    Button {
                        exportData()
                    } label: {
                        HStack {
                            Label("Экспортировать данные", systemImage: "square.and.arrow.up")
                            Spacer()
                            if isExporting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isExporting)
                    
                    Button {
                        isShowingImportPicker = true
                    } label: {
                        Label("Импортировать данные", systemImage: "square.and.arrow.down")
                    }
                    
                    Text("Экспорт создает JSON-файл со всеми данными. При импорте можно добавить данные к существующим (дубликаты автоматически пропускаются) или полностью заменить все данные.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
            .sheet(isPresented: $isShowingAddCurrency) {
                AddTrackedCurrencyView()
            }
            .fileExporter(
                isPresented: Binding(
                    get: { exportFileURL != nil },
                    set: { if !$0 { exportFileURL = nil } }
                ),
                document: exportFileURL.map { JSONFileDocument(fileURL: $0) },
                contentType: .json,
                defaultFilename: "finances_backup"
            ) { result in
                handleExportResult(result)
            }
            .fileImporter(
                isPresented: $isShowingImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImportSelection(result)
            }
            .confirmationDialog(
                "Импорт данных",
                isPresented: $isShowingImportConfirmation,
                presenting: selectedImportURL
            ) { url in
                Button("Добавить к существующим") {
                    importData(from: url, replaceExisting: false)
                }
                Button("Заменить все данные", role: .destructive) {
                    importData(from: url, replaceExisting: true)
                }
                Button("Отмена", role: .cancel) {
                    selectedImportURL = nil
                }
            } message: { _ in
                Text("Выберите способ импорта данных")
            }
            .task {
                // Приложение могло долго висеть в фоне — тихо освежаем курсы.
                let isStale = rateSync.lastUpdated.map { Date.now.timeIntervalSince($0) > 6 * 60 * 60 } ?? true
                if isStale {
                    await rateSync.run(context: modelContext)
                }
            }
            .alert("Ошибка экспорта", isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { exportErrorMessage = nil }
            } message: {
                Text(exportErrorMessage ?? "")
            }
            .alert("Ошибка импорта", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { importErrorMessage = nil }
            } message: {
                Text(importErrorMessage ?? "")
            }
            .alert("Импорт завершен", isPresented: Binding(
                get: { importSuccessMessage != nil },
                set: { if !$0 { importSuccessMessage = nil } }
            )) {
                Button("OK", role: .cancel) { importSuccessMessage = nil }
            } message: {
                Text(importSuccessMessage ?? "")
            }
        }
    }

    private func deleteTrackedRates(_ rates: [TrackedExchangeRate]) {
        for rate in rates {
            modelContext.delete(rate)
        }
        try? modelContext.save()
    }

    // MARK: - Export/Import Methods
    
    private func exportData() {
        isExporting = true
        
        Task { @MainActor in
            do {
                let fileURL = try DataExportImportManager.exportData(modelContext: modelContext)
                exportFileURL = fileURL
                isExporting = false
            } catch {
                exportErrorMessage = error.localizedDescription
                isExporting = false
            }
        }
    }
    
    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            // Файл успешно сохранен
            break
        case .failure(let error):
            exportErrorMessage = error.localizedDescription
        }
    }
    
    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            selectedImportURL = url
            isShowingImportConfirmation = true
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }
    
    private func importData(from url: URL, replaceExisting: Bool) {
        Task { @MainActor in
            do {
                try DataExportImportManager.importData(
                    from: url,
                    modelContext: modelContext,
                    replaceExisting: replaceExisting
                )
                
                let message = replaceExisting 
                    ? "Данные успешно заменены" 
                    : "Данные успешно импортированы"
                let removedDuplicates = DuplicateCleaner.autoCleanupIfEnabled(context: modelContext).count
                importSuccessMessage = removedDuplicates > 0
                    ? "\(message). Удалено дублей: \(removedDuplicates)."
                    : message
                selectedImportURL = nil
                // Рубли у импортированных операций — по курсу на их даты.
                await rateSync.run(context: modelContext)
            } catch {
                importErrorMessage = error.localizedDescription
                selectedImportURL = nil
            }
        }
    }
}

// MARK: - JSONFileDocument

struct JSONFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    let fileURL: URL
    
    init(fileURL: URL) {
        self.fileURL = fileURL
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try data.write(to: tempURL)
        self.fileURL = tempURL
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try Data(contentsOf: fileURL)
        return FileWrapper(regularFileWithContents: data)
    }
}
