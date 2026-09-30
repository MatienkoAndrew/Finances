//
//  TransactionTagSync.swift
//  Finances
//
//  Авто-применение меток к транзакциям на основе валюты.
//
//  Принцип: у `TransactionTag` есть опциональное поле `autoCurrencyCode`.
//  Если оно задано — метка автоматически навешивается на любую транзакцию,
//  у которой валюта мерчанта (`foreignCurrencyCode ?? currencyCode`)
//  совпадает с этим кодом. Это работает и при создании транзакций вручную,
//  и при импорте, и при редактировании.
//

import Foundation
import SwiftData

enum TransactionTagSync {

    /// Применяет все подходящие авто-метки к одной транзакции.
    /// Не трогает теги, которые уже стоят, и не удаляет «ручные» теги.
    /// Возвращает количество тегов, которые были добавлены.
    @discardableResult
    static func applyAutoTags(
        to transaction: Transaction,
        allTags: [TransactionTag]
    ) -> Int {
        // Переводы не привязываются к стране автоматически:
        // обычно это внутренние операции между своими счетами.
        guard transaction.kind != .transfer else { return 0 }

        guard let merchantCurrency = CurrencyTagSuggestions.merchantCurrency(of: transaction) else {
            return 0
        }

        var added = 0
        for tag in allTags {
            guard let auto = tag.autoCurrencyCode?.uppercased(),
                  !auto.isEmpty else { continue }

            if auto != merchantCurrency { continue }
            if transaction.hasTag(tag.name) { continue }

            // Пользователь уже снимал эту метку вручную — больше не навешиваем.
            if transaction.isTagManuallyExcluded(tag.name) { continue }

            transaction.addTag(tag.name)
            added += 1
        }
        return added
    }

    /// Применяет авто-метки сразу к пачке транзакций (например, после импорта).
    /// Возвращает количество транзакций, которым была добавлена хотя бы одна метка.
    @discardableResult
    static func applyAutoTags(
        to transactions: [Transaction],
        allTags: [TransactionTag]
    ) -> Int {
        let autoTags = allTags.filter {
            ($0.autoCurrencyCode?.isEmpty == false)
        }
        guard !autoTags.isEmpty else { return 0 }

        var touched = 0
        for tx in transactions {
            if applyAutoTags(to: tx, allTags: autoTags) > 0 {
                touched += 1
            }
        }
        return touched
    }
}
