//
//  DataExportImportManager.swift
//  Finances
//
//  Created by Андрей Матиенко on 27.04.2026.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Менеджер для экспорта и импорта данных приложения
@MainActor
final class DataExportImportManager {
    
    enum ExportError: LocalizedError {
        case noData
        case encodingFailed
        case saveFailed
        
        var errorDescription: String? {
            switch self {
            case .noData:
                return "Нет данных для экспорта"
            case .encodingFailed:
                return "Не удалось закодировать данные"
            case .saveFailed:
                return "Не удалось сохранить файл"
            }
        }
    }
    
    enum ImportError: LocalizedError {
        case invalidFile
        case decodingFailed
        case importFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "Неверный формат файла"
            case .decodingFailed:
                return "Не удалось декодировать данные"
            case .importFailed:
                return "Не удалось импортировать данные"
            }
        }
    }
    
    // MARK: - Export
    
    /// Экспортировать все данные в JSON
    static func exportData(modelContext: ModelContext) throws -> URL {
        let exportData = try collectAllData(modelContext: modelContext)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let jsonData = try? encoder.encode(exportData) else {
            throw ExportError.encodingFailed
        }
        
        // Создаем временный файл
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        let fileName = "finances_backup_\(dateString).json"
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try jsonData.write(to: fileURL)
            return fileURL
        } catch {
            throw ExportError.saveFailed
        }
    }
    
    private static func collectAllData(modelContext: ModelContext) throws -> ExportData {
        // Получаем все данные из базы
        let transactionDescriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\Transaction.date)])
        let transactions = try modelContext.fetch(transactionDescriptor)
        
        let rateDescriptor = FetchDescriptor<TrackedExchangeRate>()
        let trackedRates = try modelContext.fetch(rateDescriptor)
        
        let settingsDescriptor = FetchDescriptor<AppSettings>()
        let settings = try modelContext.fetch(settingsDescriptor).first

        let categories = try modelContext.fetch(FetchDescriptor<ExpenseCategoryItem>())
        let subcategories = try modelContext.fetch(FetchDescriptor<ExpenseSubcategoryItem>())
        let rules = try modelContext.fetch(FetchDescriptor<CategoryRule>())
        let accounts = try modelContext.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\Account.createdAt)]))
        let tags = try modelContext.fetch(FetchDescriptor<TransactionTag>(sortBy: [SortDescriptor(\TransactionTag.createdAt)]))

        // У счёта нет своего идентификатора — выдаём временный, им операции ссылаются на счёт.
        let accountIDs = Dictionary(uniqueKeysWithValues: accounts.map { ($0.persistentModelID, UUID().uuidString) })

        return ExportData(
            version: 3,
            exportDate: Date(),
            transactions: transactions.map { ExportableTransaction(from: $0, accountIDs: accountIDs) },
            trackedRates: trackedRates.map { ExportableTrackedRate(from: $0) },
            settings: settings.map { ExportableSettings(from: $0) },
            categories: ExpenseCategoryItem.ordered(categories).map { ExportableCategory(from: $0) },
            subcategories: subcategories.map { ExportableSubcategory(from: $0) },
            rules: rules.map { ExportableRule(from: $0) },
            accounts: accounts.map { ExportableAccount(from: $0, id: accountIDs[$0.persistentModelID]!) },
            tags: tags.map { ExportableTag(from: $0) }
        )
    }
    
    // MARK: - Import
    
    /// Импортировать данные из JSON файла
    static func importData(from url: URL, modelContext: ModelContext, replaceExisting: Bool = false) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.invalidFile
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let jsonData: Data
        do {
            jsonData = try Data(contentsOf: url)
        } catch {
            throw ImportError.invalidFile
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let exportData: ExportData
        do {
            exportData = try decoder.decode(ExportData.self, from: jsonData)
        } catch {
            print("Decoding error: \(error)")
            throw ImportError.decodingFailed
        }
        
        do {
            if replaceExisting {
                try clearAllData(modelContext: modelContext)
            }
            
            try importCategories(exportData, modelContext: modelContext, replaceExisting: replaceExisting)
            let accounts = try importAccounts(exportData, modelContext: modelContext, replaceExisting: replaceExisting)
            try importTags(exportData, modelContext: modelContext, replaceExisting: replaceExisting)
            try importAllData(exportData, accounts: accounts, modelContext: modelContext, replaceExisting: replaceExisting)
            try modelContext.save()
            SubcategoryRegistry.shared.reload(context: modelContext)
        } catch {
            print("Import error: \(error)")
            throw ImportError.importFailed
        }
    }
    
    private static func clearAllData(modelContext: ModelContext) throws {
        // Удаляем все данные
        try modelContext.delete(model: Transaction.self)
        try modelContext.delete(model: TrackedExchangeRate.self)
        try modelContext.delete(model: AppSettings.self)
    }
    
    /// Категории, подкатегории и правила. При замене берём их из копии целиком (если они в ней есть),
    /// при добавлении — только недостающие, свои настройки не трогаем.
    private static func importCategories(_ data: ExportData, modelContext: ModelContext, replaceExisting: Bool) throws {
        guard let categories = data.categories else { return }  // копия до версии 2

        if replaceExisting {
            try modelContext.delete(model: ExpenseCategoryItem.self)
            try modelContext.delete(model: ExpenseSubcategoryItem.self)
            try modelContext.delete(model: CategoryRule.self)
        }

        let existingCategories = replaceExisting ? [] : try modelContext.fetch(FetchDescriptor<ExpenseCategoryItem>())
        var categoryNames = Set(existingCategories.map { CategoryNameNormalizer.normalize($0.name) })
        var nextOrder = (existingCategories.compactMap(\.sortOrder).max() ?? -1) + 1

        for exported in categories where categoryNames.insert(CategoryNameNormalizer.normalize(exported.name)).inserted {
            let category = ExpenseCategoryItem(
                name: exported.name,
                iconName: exported.iconName,
                emoji: exported.emoji,
                colorHex: exported.colorHex,
                isSystem: exported.isSystem
            )
            category.sortOrder = replaceExisting ? exported.sortOrder : nextOrder
            nextOrder += 1
            modelContext.insert(category)
        }

        let existingSubcategories = replaceExisting ? [] : try modelContext.fetch(FetchDescriptor<ExpenseSubcategoryItem>())
        var subcategoryKeys = Set(existingSubcategories.map { CategoryNameNormalizer.normalize($0.categoryName) + "|" + $0.name })
        for exported in data.subcategories ?? []
        where subcategoryKeys.insert(CategoryNameNormalizer.normalize(exported.categoryName) + "|" + exported.name).inserted {
            modelContext.insert(ExpenseSubcategoryItem(
                name: exported.name,
                emoji: exported.emoji,
                categoryName: exported.categoryName,
                sortOrder: exported.sortOrder
            ))
        }

        let existingRules = replaceExisting ? [] : try modelContext.fetch(FetchDescriptor<CategoryRule>())
        var patterns = Set(existingRules.map { $0.pattern.uppercased() })
        for exported in data.rules ?? [] where patterns.insert(exported.pattern.uppercased()).inserted {
            modelContext.insert(CategoryRule(
                pattern: exported.pattern,
                categoryName: exported.categoryName,
                subcategoryName: exported.subcategoryName,
                priority: exported.priority,
                isEnabled: exported.isEnabled,
                createdAt: exported.createdAt
            ))
        }
    }

    /// Счета. При замене — ровно как в копии, при добавлении — недостающие (совпадение по имени и валюте).
    /// Возвращает счёт по идентификатору из копии, чтобы привязать к нему операции.
    private static func importAccounts(_ data: ExportData, modelContext: ModelContext, replaceExisting: Bool) throws -> [String: Account] {
        guard let exportedAccounts = data.accounts else { return [:] }  // копия до версии 3

        if replaceExisting {
            try modelContext.delete(model: Account.self)
        }

        let existing = replaceExisting ? [] : try modelContext.fetch(FetchDescriptor<Account>())
        func key(_ name: String, _ currency: String) -> String {
            CategoryNameNormalizer.normalize(name) + "|" + currency.uppercased()
        }
        var byKey = Dictionary(existing.map { (key($0.name, $0.currencyCode), $0) }, uniquingKeysWith: { first, _ in first })

        var byID: [String: Account] = [:]
        for exported in exportedAccounts {
            let accountKey = key(exported.name, exported.currencyCode)
            if let account = byKey[accountKey] {
                byID[exported.id] = account
                continue
            }
            let account = Account(
                name: exported.name,
                currencyCode: exported.currencyCode,
                typeRaw: exported.typeRaw,
                note: exported.note,
                isArchived: exported.isArchived,
                createdAt: exported.createdAt
            )
            modelContext.insert(account)
            byKey[accountKey] = account
            byID[exported.id] = account
        }
        return byID
    }

    /// Метки. При замене — ровно как в копии, при добавлении — только новые по имени.
    private static func importTags(_ data: ExportData, modelContext: ModelContext, replaceExisting: Bool) throws {
        guard let exportedTags = data.tags else { return }  // копия до версии 3

        if replaceExisting {
            try modelContext.delete(model: TransactionTag.self)
        }

        let existing = replaceExisting ? [] : try modelContext.fetch(FetchDescriptor<TransactionTag>())
        var names = Set(existing.map { CategoryNameNormalizer.normalize($0.name) })
        for exported in exportedTags where names.insert(CategoryNameNormalizer.normalize(exported.name)).inserted {
            modelContext.insert(TransactionTag(
                name: exported.name,
                startDate: exported.startDate,
                endDate: exported.endDate,
                icon: exported.icon,
                colorHex: exported.colorHex,
                createdAt: exported.createdAt,
                autoCurrencyCode: exported.autoCurrencyCode
            ))
        }
    }

    private static func makeTransaction(_ exported: ExportableTransaction, accounts: [String: Account]) -> Transaction {
        Transaction(
            date: exported.date,
            kindRaw: exported.kindRaw,
            amount: exported.amount,
            currencyCode: exported.currencyCode,
            toAmount: exported.toAmount,
            toCurrencyCode: exported.toCurrencyCode,
            details: exported.details,
            foreignAmount: exported.foreignAmount,
            foreignCurrencyCode: exported.foreignCurrencyCode,
            rubAmount: exported.rubAmount,
            categoryName: exported.categoryName,
            subcategoryName: exported.subcategoryName,
            isCategoryManuallySet: exported.isCategoryManuallySet ?? false,
            note: exported.note,
            tagNames: exported.tagNames,
            manuallyExcludedTagNames: exported.manuallyExcludedTagNames,
            fingerprint: exported.fingerprint,
            sourceFileName: exported.sourceFileName,
            importedAt: exported.importedAt,
            createdAt: exported.createdAt,
            fromAccount: exported.fromAccountID.flatMap { accounts[$0] },
            toAccount: exported.toAccountID.flatMap { accounts[$0] }
        )
    }

    private static func importAllData(_ data: ExportData, accounts: [String: Account], modelContext: ModelContext, replaceExisting: Bool = false) throws {
        // Импортируем отслеживаемые курсы валют
        if replaceExisting {
            // При замене просто добавляем все
            for exportRate in data.trackedRates {
                let rate = TrackedExchangeRate(
                    code: exportRate.code,
                    displayName: exportRate.displayName,
                    flag: exportRate.flag,
                    rubPerUnit: exportRate.rubPerUnit
                )
                modelContext.insert(rate)
            }
        } else {
            // При добавлении - проверяем, нет ли уже такой валюты
            let existingRatesDescriptor = FetchDescriptor<TrackedExchangeRate>()
            let existingRates = try modelContext.fetch(existingRatesDescriptor)
            let existingCodes = Set(existingRates.map { $0.code.uppercased() })
            
            for exportRate in data.trackedRates {
                if !existingCodes.contains(exportRate.code.uppercased()) {
                    let rate = TrackedExchangeRate(
                        code: exportRate.code,
                        displayName: exportRate.displayName,
                        flag: exportRate.flag,
                        rubPerUnit: exportRate.rubPerUnit
                    )
                    modelContext.insert(rate)
                }
            }
        }
        
        // Импортируем настройки
        if let exportSettings = data.settings {
            if replaceExisting {
                // При замене просто добавляем
                let settings = AppSettings(kztPerRub: exportSettings.kztPerRub)
                modelContext.insert(settings)
            } else {
                // При добавлении - обновляем существующие настройки
                let settingsDescriptor = FetchDescriptor<AppSettings>()
                let existingSettings = try modelContext.fetch(settingsDescriptor).first
                
                if let existing = existingSettings {
                    existing.kztPerRub = exportSettings.kztPerRub
                } else {
                    let settings = AppSettings(kztPerRub: exportSettings.kztPerRub)
                    modelContext.insert(settings)
                }
            }
        }
        
        // Подгружаем существующие метки один раз — будем применять авто-метки
        // ко всему импорту разом, чтобы новые транзакции в иностранных валютах
        // автоматически получили метки-страны (если такие auto-метки уже созданы).
        let allTagsDescriptor = FetchDescriptor<TransactionTag>()
        let allTags = (try? modelContext.fetch(allTagsDescriptor)) ?? []
        var importedTransactionsForAutoTagging: [Transaction] = []

        // Импортируем транзакции
        if replaceExisting {
            // При замене просто добавляем все
            for exportTransaction in data.transactions {
                let transaction = makeTransaction(exportTransaction, accounts: accounts)

                modelContext.insert(transaction)
                importedTransactionsForAutoTagging.append(transaction)
            }
        } else {
            // При добавлении - проверяем на дубликаты по fingerprint
            let existingTransactionsDescriptor = FetchDescriptor<Transaction>()
            let existingTransactions = try modelContext.fetch(existingTransactionsDescriptor)
            let existingFingerprints = Set(existingTransactions.compactMap { $0.fingerprint })
            
            var addedCount = 0
            var skippedCount = 0
            
            for exportTransaction in data.transactions {
                // Пропускаем, если есть fingerprint и он уже существует
                if let fingerprint = exportTransaction.fingerprint, 
                   !fingerprint.isEmpty,
                   existingFingerprints.contains(fingerprint) {
                    skippedCount += 1
                    continue
                }
                
                let transaction = makeTransaction(exportTransaction, accounts: accounts)
                
                modelContext.insert(transaction)
                importedTransactionsForAutoTagging.append(transaction)
                addedCount += 1
            }

            print("Импорт: добавлено \(addedCount), пропущено дубликатов \(skippedCount)")
        }

        // Прогоняем все только что импортированные транзакции через авто-теги.
        // Если в системе есть метка с `autoCurrencyCode` (например, «Гонконг» → HKD),
        // подходящие импортированные транзакции автоматически получат её.
        TransactionTagSync.applyAutoTags(
            to: importedTransactionsForAutoTagging,
            allTags: allTags
        )
    }
}

// MARK: - Export Data Structures

struct ExportData: Codable {
    let version: Int
    let exportDate: Date
    let transactions: [ExportableTransaction]
    let trackedRates: [ExportableTrackedRate]
    let settings: ExportableSettings?
    // С версии 2; в старых копиях их нет — тогда категории при импорте не трогаем.
    var categories: [ExportableCategory]? = nil
    var subcategories: [ExportableSubcategory]? = nil
    var rules: [ExportableRule]? = nil
    // С версии 3; в старых копиях их нет — тогда счета и метки при импорте не трогаем.
    var accounts: [ExportableAccount]? = nil
    var tags: [ExportableTag]? = nil
}

struct ExportableAccount: Codable {
    /// Идентификатор внутри копии — по нему операции ссылаются на счёт.
    let id: String
    let name: String
    let currencyCode: String
    let typeRaw: String
    let note: String?
    let isArchived: Bool
    let createdAt: Date

    init(from account: Account, id: String) {
        self.id = id
        self.name = account.name
        self.currencyCode = account.currencyCode
        self.typeRaw = account.typeRaw
        self.note = account.note
        self.isArchived = account.isArchived
        self.createdAt = account.createdAt
    }
}

struct ExportableTag: Codable {
    let name: String
    let startDate: Date?
    let endDate: Date?
    let icon: String?
    let colorHex: String?
    let createdAt: Date
    let autoCurrencyCode: String?

    init(from tag: TransactionTag) {
        self.name = tag.name
        self.startDate = tag.startDate
        self.endDate = tag.endDate
        self.icon = tag.icon
        self.colorHex = tag.colorHex
        self.createdAt = tag.createdAt
        self.autoCurrencyCode = tag.autoCurrencyCode
    }
}

struct ExportableCategory: Codable {
    let name: String
    let iconName: String
    let emoji: String?
    let colorHex: String
    let isSystem: Bool
    let sortOrder: Int?

    init(from category: ExpenseCategoryItem) {
        self.name = category.name
        self.iconName = category.iconName
        self.emoji = category.emoji
        self.colorHex = category.colorHex
        self.isSystem = category.isSystem
        self.sortOrder = category.sortOrder
    }
}

struct ExportableSubcategory: Codable {
    let name: String
    let emoji: String
    let categoryName: String
    let sortOrder: Int

    init(from subcategory: ExpenseSubcategoryItem) {
        self.name = subcategory.name
        self.emoji = subcategory.emoji
        self.categoryName = subcategory.categoryName
        self.sortOrder = subcategory.sortOrder
    }
}

struct ExportableRule: Codable {
    let pattern: String
    let categoryName: String
    let subcategoryName: String?
    let priority: Int
    let isEnabled: Bool
    let createdAt: Date

    init(from rule: CategoryRule) {
        self.pattern = rule.pattern
        self.categoryName = rule.categoryName
        self.subcategoryName = rule.subcategoryName
        self.priority = rule.priority
        self.isEnabled = rule.isEnabled
        self.createdAt = rule.createdAt
    }
}

struct ExportableTransaction: Codable {
    let id: String
    let date: Date
    let kindRaw: String
    let amount: Double
    let currencyCode: String
    let toAmount: Double?
    let toCurrencyCode: String?
    let details: String
    let foreignAmount: Double?
    let foreignCurrencyCode: String?
    let rubAmount: Double?
    let categoryName: String?
    /// С версии 2; Optional — старые копии декодируются.
    let subcategoryName: String?
    /// Сохраняется в бэкапе, чтобы ручные пометки категорий
    /// переживали полный экспорт/импорт. Optional => старые бэкапы
    /// декодируются корректно (поле станет nil).
    let isCategoryManuallySet: Bool?
    let note: String?
    let tagNames: [String]?
    /// С версии 3: снятые вручную метки, чтобы авто-метки не вернули их после импорта.
    let manuallyExcludedTagNames: [String]?
    /// С версии 3: счета списания и зачисления (id из `ExportData.accounts`).
    let fromAccountID: String?
    let toAccountID: String?
    let fingerprint: String?
    let sourceFileName: String?
    let importedAt: Date?
    let createdAt: Date
    
    init(from transaction: Transaction, accountIDs: [PersistentIdentifier: String]) {
        self.id = UUID().uuidString
        self.date = transaction.date
        self.kindRaw = transaction.kindRaw
        self.amount = transaction.amount
        self.currencyCode = transaction.currencyCode
        self.toAmount = transaction.toAmount
        self.toCurrencyCode = transaction.toCurrencyCode
        self.details = transaction.details
        self.foreignAmount = transaction.foreignAmount
        self.foreignCurrencyCode = transaction.foreignCurrencyCode
        self.rubAmount = transaction.rubAmount
        self.categoryName = transaction.categoryName
        self.subcategoryName = transaction.subcategoryName
        self.isCategoryManuallySet = transaction.isCategoryManuallySet
        self.note = transaction.note
        self.tagNames = transaction.tagNames
        self.manuallyExcludedTagNames = transaction.manuallyExcludedTagNames
        self.fromAccountID = transaction.fromAccount.flatMap { accountIDs[$0.persistentModelID] }
        self.toAccountID = transaction.toAccount.flatMap { accountIDs[$0.persistentModelID] }
        self.fingerprint = transaction.fingerprint
        self.sourceFileName = transaction.sourceFileName
        self.importedAt = transaction.importedAt
        self.createdAt = transaction.createdAt
    }
}

struct ExportableTrackedRate: Codable {
    let code: String
    let displayName: String
    let flag: String
    let rubPerUnit: Double
    
    init(from rate: TrackedExchangeRate) {
        self.code = rate.code
        self.displayName = rate.displayName
        self.flag = rate.flag
        self.rubPerUnit = rate.rubPerUnit
    }
}

struct ExportableSettings: Codable {
    let kztPerRub: Double
    
    init(from settings: AppSettings) {
        self.kztPerRub = settings.kztPerRub
    }
}
