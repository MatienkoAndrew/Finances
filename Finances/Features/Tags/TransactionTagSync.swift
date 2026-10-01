//
//  TransactionTagSync.swift
//  Finances
//
//  Авто-применение меток к транзакциям на основе валюты.
//
//  Принцип: у `TransactionTag` есть опциональное поле `autoCurrencyCode`.
//  Если оно задано — метка автоматически навешивается на любую транзакцию,
//  совершённую в стране этой валюты. Обычно страна — это валюта мерчанта
//  (`foreignCurrencyCode ?? currencyCode`), но её уточняет `TripCurrencyResolver`:
//  доллары и юани, потраченные в даты поездки в Корею, получают «Южную Корею»,
//  а не «США» или «Китай». Это работает и при создании транзакций вручную,
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
        allTags: [TransactionTag],
        context: ModelContext
    ) -> Int {
        let autoTags = autoTags(in: allTags)
        guard !autoTags.isEmpty else { return 0 }
        let resolver = TripCurrencyResolver(around: transaction, tags: allTags, context: context)
        return applyAutoTags(to: transaction, autoTags: autoTags, resolver: resolver)
    }

    /// Применяет авто-метки сразу к пачке транзакций (например, после импорта).
    /// Возвращает количество транзакций, которым была добавлена хотя бы одна метка.
    @discardableResult
    static func applyAutoTags(
        to transactions: [Transaction],
        context: ModelContext
    ) -> Int {
        let tags = (try? context.fetch(FetchDescriptor<TransactionTag>())) ?? []
        let autoTags = autoTags(in: tags)
        guard !autoTags.isEmpty else { return 0 }

        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? transactions
        let resolver = TripCurrencyResolver(transactions: all, tags: tags)

        var touched = 0
        for tx in transactions {
            if applyAutoTags(to: tx, autoTags: autoTags, resolver: resolver) > 0 {
                touched += 1
            }
        }
        return touched
    }

    /// Приводит метки в порядок: убирает копии меток с одинаковым именем
    /// и переставляет авто-метки — доллары, потраченные в Корее, переезжают из «США»
    /// в «Южную Корею». Запускается при старте и после правки метки.
    static func run(context: ModelContext) {
        let byAge = FetchDescriptor<TransactionTag>(sortBy: [SortDescriptor(\.createdAt)])
        guard let tags = try? context.fetch(byAge),
              let transactions = try? context.fetch(FetchDescriptor<Transaction>()) else { return }

        // Операции ссылаются на метку по имени, поэтому лишняя копия
        // (например, от двойного касания по подсказке) просто удаляется.
        var names = Set<String>()
        var kept: [TransactionTag] = []
        var changed = false
        for tag in tags {
            if names.insert(tag.name).inserted {
                kept.append(tag)
            } else {
                context.delete(tag)
                changed = true
            }
        }

        let autoTags = autoTags(in: kept)
        if !autoTags.isEmpty {
            let resolver = TripCurrencyResolver(transactions: transactions, tags: kept)
            for tx in transactions where tx.kind != .transfer {
                if let merchant = CurrencyTagSuggestions.merchantCurrency(of: tx),
                   let location = resolver.locationCurrency(of: tx),
                   location != merchant {
                    // Платили долларами, но не в США: метка валюты здесь не к месту.
                    for tag in autoTags where tag.autoCurrencyCode?.uppercased() == merchant && tx.hasTag(tag.name) {
                        tx.removeTag(tag.name)
                        changed = true
                    }
                }
                if applyAutoTags(to: tx, autoTags: autoTags, resolver: resolver) > 0 {
                    changed = true
                }
            }
        }

        if changed {
            try? context.save()
        }
    }

    // MARK: - Private

    private static func autoTags(in tags: [TransactionTag]) -> [TransactionTag] {
        tags.filter { $0.autoCurrencyCode?.isEmpty == false }
    }

    private static func applyAutoTags(
        to transaction: Transaction,
        autoTags: [TransactionTag],
        resolver: TripCurrencyResolver
    ) -> Int {
        // Переводы не привязываются к стране автоматически:
        // обычно это внутренние операции между своими счетами.
        guard transaction.kind != .transfer,
              let location = resolver.locationCurrency(of: transaction) else { return 0 }

        var added = 0
        for tag in autoTags where tag.autoCurrencyCode?.uppercased() == location {
            if transaction.hasTag(tag.name) { continue }

            // Пользователь уже снимал эту метку вручную — больше не навешиваем.
            if transaction.isTagManuallyExcluded(tag.name) { continue }

            transaction.addTag(tag.name)
            added += 1
        }
        return added
    }
}
