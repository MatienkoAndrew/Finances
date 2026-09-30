//
//  PDFImportResult.swift
//  Finances
//
//  Created by Андрей Матиенко on 31.03.2026.
//


import Foundation

struct PDFImportResult {
    /// Метка импорта: у всех добавленных операций такой же `importedAt`.
    let importedAt: Date
    let fileName: String
    let accountsToCreate: [Account]
    /// Новые операции — их нужно вставить в контекст.
    let transactions: [Transaction]
    /// Строки выписки, которые уже были в базе.
    let skippedDuplicatesCount: Int
    /// Уже импортированные валютные операции, у которых предварительная сумма
    /// в тенге заменена на окончательную.
    let settledAmountsCount: Int
    /// Уже импортированные операции, у которых исправлен знак (возврат, курсовая разница).
    let repairedCount: Int
    /// Что именно поменялось у существующих операций — для отмены импорта.
    let modifications: [TransactionModification]
    /// Типы операций, по которым сумма не сошлась с итогами выписки.
    let mismatchedOperationTypes: [String]
    /// Строки, похожие на операции, которые не удалось разобрать.
    let unrecognizedLinesCount: Int

    var summaryMessage: String {
        var parts = ["Новых операций: \(transactions.count)"]

        if skippedDuplicatesCount > 0 {
            parts.append("уже были в базе: \(skippedDuplicatesCount)")
        }
        if settledAmountsCount > 0 {
            parts.append("уточнены суммы: \(settledAmountsCount)")
        }
        if repairedCount > 0 {
            parts.append("исправлены: \(repairedCount)")
        }

        var message = parts.joined(separator: ", ") + "."

        if !accountsToCreate.isEmpty {
            message += "\nСозданы счета: \(accountsToCreate.map(\.name).joined(separator: ", "))."
        }

        if !mismatchedOperationTypes.isEmpty || unrecognizedLinesCount > 0 {
            message += "\n⚠️ Часть выписки могла не распознаться"
            if !mismatchedOperationTypes.isEmpty {
                message += " — не сходятся итоги: \(mismatchedOperationTypes.joined(separator: ", "))"
            }
            message += ". Проверь операции за этот период."
        }

        return message
    }
}
