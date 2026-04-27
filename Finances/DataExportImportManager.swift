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
        
        let accountDescriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\Account.name)])
        let accounts = try modelContext.fetch(accountDescriptor)
        
        let categoryRuleDescriptor = FetchDescriptor<CategoryRule>()
        let categoryRules = try modelContext.fetch(categoryRuleDescriptor)
        
        let categoryDescriptor = FetchDescriptor<ExpenseCategoryItem>()
        let categories = try modelContext.fetch(categoryDescriptor)
        
        let rateDescriptor = FetchDescriptor<TrackedExchangeRate>()
        let trackedRates = try modelContext.fetch(rateDescriptor)
        
        let settingsDescriptor = FetchDescriptor<AppSettings>()
        let settings = try modelContext.fetch(settingsDescriptor).first
        
        let tagsDescriptor = FetchDescriptor<TransactionTag>()
        let tags = try modelContext.fetch(tagsDescriptor)
        
        return ExportData(
            version: 1,
            exportDate: Date(),
            transactions: transactions.map { ExportableTransaction(from: $0) },
            accounts: accounts.map { ExportableAccount(from: $0) },
            categoryRules: categoryRules.map { ExportableCategoryRule(from: $0) },
            categories: categories.map { ExportableCategory(from: $0) },
            trackedRates: trackedRates.map { ExportableTrackedRate(from: $0) },
            settings: settings.map { ExportableSettings(from: $0) },
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
            
            try importAllData(exportData, modelContext: modelContext)
            try modelContext.save()
        } catch {
            print("Import error: \(error)")
            throw ImportError.importFailed
        }
    }
    
    private static func clearAllData(modelContext: ModelContext) throws {
        // Удаляем все данные
        try modelContext.delete(model: Transaction.self)
        try modelContext.delete(model: Account.self)
        try modelContext.delete(model: CategoryRule.self)
        try modelContext.delete(model: ExpenseCategoryItem.self)
        try modelContext.delete(model: TrackedExchangeRate.self)
        try modelContext.delete(model: AppSettings.self)
        try modelContext.delete(model: TransactionTag.self)
    }
    
    private static func importAllData(_ data: ExportData, modelContext: ModelContext) throws {
        // Словари для связи ID
        var accountMap: [String: Account] = [:]
        
        // Импортируем аккаунты
        for exportAccount in data.accounts {
            let account = Account(
                name: exportAccount.name,
                currencyCode: exportAccount.currencyCode,
                initialBalance: exportAccount.initialBalance,
                color: exportAccount.color,
                order: exportAccount.order,
                isActive: exportAccount.isActive
            )
            modelContext.insert(account)
            accountMap[exportAccount.id] = account
        }
        
        // Импортируем категории
        for exportCategory in data.categories {
            let category = ExpenseCategoryItem(
                title: exportCategory.title,
                color: exportCategory.color,
                order: exportCategory.order
            )
            modelContext.insert(category)
        }
        
        // Импортируем правила категорий
        for exportRule in data.categoryRules {
            let rule = CategoryRule(
                detailsContains: exportRule.detailsContains,
                categoryName: exportRule.categoryName
            )
            rule.isActive = exportRule.isActive
            modelContext.insert(rule)
        }
        
        // Импортируем отслеживаемые курсы валют
        for exportRate in data.trackedRates {
            let rate = TrackedExchangeRate(
                code: exportRate.code,
                rubPerUnit: exportRate.rubPerUnit
            )
            modelContext.insert(rate)
        }
        
        // Импортируем настройки
        if let exportSettings = data.settings {
            let settings = AppSettings()
            settings.kztPerRub = exportSettings.kztPerRub
            modelContext.insert(settings)
        }
        
        // Импортируем метки
        for exportTag in data.tags {
            let tag = TransactionTag(
                name: exportTag.name,
                color: exportTag.color,
                order: exportTag.order
            )
            modelContext.insert(tag)
        }
        
        // Импортируем транзакции
        for exportTransaction in data.transactions {
            let transaction = Transaction(
                date: exportTransaction.date,
                kindRaw: exportTransaction.kindRaw,
                amount: exportTransaction.amount,
                currencyCode: exportTransaction.currencyCode,
                toAmount: exportTransaction.toAmount,
                toCurrencyCode: exportTransaction.toCurrencyCode,
                details: exportTransaction.details,
                foreignAmount: exportTransaction.foreignAmount,
                foreignCurrencyCode: exportTransaction.foreignCurrencyCode,
                rubAmount: exportTransaction.rubAmount,
                categoryName: exportTransaction.categoryName,
                note: exportTransaction.note,
                tagNames: exportTransaction.tagNames,
                fingerprint: exportTransaction.fingerprint,
                sourceFileName: exportTransaction.sourceFileName,
                importedAt: exportTransaction.importedAt,
                createdAt: exportTransaction.createdAt
            )
            
            // Связываем с аккаунтами
            if let fromAccountId = exportTransaction.fromAccountId {
                transaction.fromAccount = accountMap[fromAccountId]
            }
            if let toAccountId = exportTransaction.toAccountId {
                transaction.toAccount = accountMap[toAccountId]
            }
            
            modelContext.insert(transaction)
        }
    }
}

// MARK: - Export Data Structures

struct ExportData: Codable {
    let version: Int
    let exportDate: Date
    let transactions: [ExportableTransaction]
    let accounts: [ExportableAccount]
    let categoryRules: [ExportableCategoryRule]
    let categories: [ExportableCategory]
    let trackedRates: [ExportableTrackedRate]
    let settings: ExportableSettings?
    let tags: [ExportableTag]
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
    let note: String?
    let tagNames: [String]?
    let fingerprint: String?
    let sourceFileName: String?
    let importedAt: Date?
    let createdAt: Date
    let fromAccountId: String?
    let toAccountId: String?
    
    init(from transaction: Transaction) {
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
        self.note = transaction.note
        self.tagNames = transaction.tagNames
        self.fingerprint = transaction.fingerprint
        self.sourceFileName = transaction.sourceFileName
        self.importedAt = transaction.importedAt
        self.createdAt = transaction.createdAt
        self.fromAccountId = transaction.fromAccount?.persistentModelID.hashValue.description
        self.toAccountId = transaction.toAccount?.persistentModelID.hashValue.description
    }
}

struct ExportableAccount: Codable {
    let id: String
    let name: String
    let currencyCode: String
    let initialBalance: Double
    let color: String
    let order: Int
    let isActive: Bool
    
    init(from account: Account) {
        self.id = account.persistentModelID.hashValue.description
        self.name = account.name
        self.currencyCode = account.currencyCode
        self.initialBalance = account.initialBalance
        self.color = account.color
        self.order = account.order
        self.isActive = account.isActive
    }
}

struct ExportableCategoryRule: Codable {
    let detailsContains: String
    let categoryName: String
    let isActive: Bool
    
    init(from rule: CategoryRule) {
        self.detailsContains = rule.detailsContains
        self.categoryName = rule.categoryName
        self.isActive = rule.isActive
    }
}

struct ExportableCategory: Codable {
    let title: String
    let color: String
    let order: Int
    
    init(from category: ExpenseCategoryItem) {
        self.title = category.title
        self.color = category.color
        self.order = category.order
    }
}

struct ExportableTrackedRate: Codable {
    let code: String
    let rubPerUnit: Double
    
    init(from rate: TrackedExchangeRate) {
        self.code = rate.code
        self.rubPerUnit = rate.rubPerUnit
    }
}

struct ExportableSettings: Codable {
    let kztPerRub: Double
    
    init(from settings: AppSettings) {
        self.kztPerRub = settings.kztPerRub
    }
}

struct ExportableTag: Codable {
    let name: String
    let color: String
    let order: Int
    
    init(from tag: TransactionTag) {
        self.name = tag.name
        self.color = tag.color
        self.order = tag.order
    }
}
