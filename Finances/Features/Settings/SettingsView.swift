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

    @Query
    private var categories: [ExpenseCategoryItem]

    @Query
    private var tags: [TransactionTag]

    @State private var isExporting = false
    @State private var exportFileURL: URL?
    @State private var isShowingImportPicker = false
    @State private var isShowingImportConfirmation = false
    @State private var selectedImportURL: URL?
    @State private var exportErrorMessage: String?
    @State private var importErrorMessage: String?
    @State private var importSuccessMessage: String?
    @State private var importCount = 0

    private var rateSync: ExchangeRateSync { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ratesSection
                    accountingSection
                    checksSection
                    backupSection
                    appFooter
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Настройки")
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
            .onAppear {
                importCount = ImportHistory.loadRecords().count
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

    // MARK: - Sections

    /// Лента курсов: самые используемые валюты, «Все» — полный список.
    private var ratesSection: some View {
        let counts = CurrencyRatesSummary.operationCounts(transactions)
        let table = RubRateTable(rates: dailyRates)
        let rates = CurrencyRatesSummary.sorted(trackedRates, by: counts)

        return VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader("Курсы валют") {
                NavigationLink {
                    CurrencyRatesView()
                } label: {
                    Text("Все")
                        .font(.subheadline.weight(.semibold))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(rates.prefix(8)) { rate in
                        NavigationLink {
                            CurrencyRatesView()
                        } label: {
                            CurrencyRateTile(rate: rate, latest: table.latest(rate.code))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollClipDisabled()
            .padding(.horizontal, -16)

            HStack(spacing: 8) {
                Text(ratesStatus)
                    .font(.caption)
                    .foregroundStyle(rateSync.lastError == nil ? Color.secondary : Color.orange)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button {
                    Task { await rateSync.run(context: modelContext) }
                } label: {
                    Group {
                        if rateSync.isRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(rateSync.isRunning)
                .accessibilityLabel("Обновить курсы")
            }
            .padding(.horizontal, 4)
        }
    }

    private var ratesStatus: String {
        if rateSync.isRunning { return "Обновляем курсы…" }
        if rateSync.lastError != nil { return "Нет связи — считаем по последним известным курсам." }
        guard let updated = rateSync.lastUpdated else { return "Курсы ЦБ РФ на дату каждой операции." }
        return "ЦБ РФ · обновлено \(CurrencyRatesSummary.updatedText(updated))"
    }

    private var accountingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader("Учёт")

            SettingsCard {
                NavigationLink {
                    CategoriesView()
                } label: {
                    SettingsRow(title: "Категории", systemImage: "square.grid.2x2.fill", color: .orange, value: categories.isEmpty ? nil : "\(categories.count)")
                }
                .buttonStyle(SettingsPressStyle())

                SettingsDivider()

                NavigationLink {
                    TagsManagementView()
                } label: {
                    SettingsRow(title: "Метки", systemImage: "tag.fill", color: .blue, value: tags.isEmpty ? nil : "\(tags.count)")
                }
                .buttonStyle(SettingsPressStyle())

                SettingsDivider()

                NavigationLink {
                    LearnedMerchantsView()
                } label: {
                    SettingsRow(title: "Запомненные мерчанты", systemImage: "storefront.fill", color: .green)
                }
                .buttonStyle(SettingsPressStyle())

                SettingsDivider()

                AICategorizationRow()
            }
        }
    }

    private var checksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader("Импорт и проверка")

            SettingsCard {
                NavigationLink {
                    ImportHistoryView()
                } label: {
                    SettingsRow(title: "История импортов", systemImage: "clock.arrow.circlepath", color: .indigo, value: importCount > 0 ? "\(importCount)" : nil)
                }
                .buttonStyle(SettingsPressStyle())

                SettingsDivider()

                NavigationLink {
                    DuplicatesView()
                } label: {
                    SettingsRow(title: "Поиск дублей", systemImage: "doc.on.doc.fill", color: .red)
                }
                .buttonStyle(SettingsPressStyle())
            }
        }
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader("Резервная копия")

            HStack(spacing: 12) {
                backupTile(
                    title: "Экспорт",
                    subtitle: "Все данные в JSON-файл",
                    systemImage: "square.and.arrow.up",
                    color: .blue,
                    isBusy: isExporting,
                    action: exportData
                )
                backupTile(
                    title: "Импорт",
                    subtitle: "Добавить или заменить",
                    systemImage: "square.and.arrow.down",
                    color: .teal,
                    isBusy: false
                ) {
                    isShowingImportPicker = true
                }
            }

            Text("При импорте можно добавить данные к существующим — дубли пропускаются — или полностью заменить всё.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func backupTile(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        isBusy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SettingsIcon(systemImage: systemImage, color: color, size: 40)
                    Spacer()
                    if isBusy {
                        ProgressView()
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .buttonStyle(SettingsPressStyle())
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .disabled(isBusy)
    }

    private var appFooter: some View {
        let info = Bundle.main.infoDictionary
        let name = info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String ?? "Finances"
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"

        return VStack(spacing: 2) {
            Text(name)
                .font(.footnote.weight(.semibold))
            Text("Версия \(version) (\(build))")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
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
