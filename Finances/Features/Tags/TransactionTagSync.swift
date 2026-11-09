//
//  TransactionTagSync.swift
//  Finances
//
//  Метки по датам: метка с периодом стоит на операциях за эти дни.
//  Был в Корее с 12 по 29 сентября — все операции за эти даты получают
//  «Южную Корею». Если у метки заданы валюты поездки (Япония — JPY), сами
//  метку получают только операции в них, а остальные расходы за эти дни
//  (доллары, тенге) ждут решения на экране метки. Новые операции за эти дни
//  (добавленные вручную или из выписки) раскладываются так же.
//  Ручные решения пользователя (снял или подтвердил метку) не перетираются.
//

import Foundation
import SwiftData

enum TransactionTagSync {

    /// Дни периода метки: от начала первого дня до начала дня после последнего.
    static func days(from start: Date?, to end: Date?, calendar: Calendar = .current) -> Range<Date>? {
        guard let start, let end else { return nil }
        let first = calendar.startOfDay(for: start)
        guard let afterLast = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)),
              first < afterLast else { return nil }
        return first..<afterLast
    }

    /// Что делать с операцией за даты метки.
    enum Decision: Equatable {
        /// Ставим метку сами.
        case tag
        /// Расход не в валюте поездки — ждёт решения пользователя.
        case review
        /// Доход или перевод не в валюте поездки — не трогаем.
        case skip
    }

    /// Валюты, в которых прошла операция: у покупки за границей — валюта страны,
    /// у перевода — обе стороны (снятие в банкомате: тенге → наличные йены).
    static func paymentCurrencies(of transaction: Transaction) -> Set<String> {
        let codes: [String?]
        switch transaction.kind {
        case .transfer:
            codes = [transaction.currencyCode, transaction.toCurrencyCode]
        case .expense, .income:
            codes = [transaction.foreignCurrencyCode ?? transaction.currencyCode]
        }
        return Set(codes.compactMap { $0 }.map { CurrencyDisplay.normalizedCode(from: $0) })
    }

    /// Решение для операции, попавшей в даты метки. Без валют поездки метка
    /// ставится на всё, как раньше. С валютами — только на операции в них;
    /// остальные расходы (доллары в Японии, комиссия в тенге) ждут решения.
    static func decision(for transaction: Transaction, tag: TransactionTag) -> Decision {
        decision(for: transaction, currencies: tag.tripCurrencyCodes)
    }

    static func decision(for transaction: Transaction, currencies: Set<String>) -> Decision {
        guard !currencies.isEmpty else { return .tag }

        if !paymentCurrencies(of: transaction).isDisjoint(with: currencies) {
            return .tag
        }
        // Курсовая разница — довесок к покупке за границей, своей валюты у неё нет.
        if transaction.isExchangeRateDifference {
            return .tag
        }
        return transaction.kind == .expense ? .review : .skip
    }

    /// Метку сохранили в редакторе: раскладываем операции её периода по правилу
    /// (метка, на рассмотрение или мимо), а с дней, которые выпали из старого
    /// периода, метку снимаем. Ручные решения пользователя не трогаем.
    static func applyPeriod(
        of tag: TransactionTag,
        previousStart: Date?,
        previousEnd: Date?,
        transactions: [Transaction]
    ) {
        let current = days(from: tag.startDate, to: tag.endDate)
        let previous = days(from: previousStart, to: previousEnd)
        let name = tag.name

        for transaction in transactions {
            if let current, current.contains(transaction.date) {
                if transaction.isTagManuallyExcluded(name) {
                    transaction.setTagPending(name, false)
                    continue
                }
                if transaction.isTagManuallyIncluded(name) {
                    transaction.addTag(name)
                    transaction.setTagPending(name, false)
                    continue
                }

                switch decision(for: transaction, tag: tag) {
                case .tag:
                    transaction.addTag(name)
                    transaction.setTagPending(name, false)
                case .review:
                    // Уже стоявшая метка (по датам) тоже уходит на рассмотрение:
                    // не отличить, поставило её правило или пользователь.
                    transaction.removeTag(name)
                    transaction.setTagPending(name, true)
                case .skip:
                    transaction.removeTag(name)
                    transaction.setTagPending(name, false)
                }
            } else if let previous, previous.contains(transaction.date) {
                transaction.removeTag(name)
                transaction.setTagPending(name, false)
            }
        }
    }

    /// Новая или изменённая операция получает метки, в период которых попала,
    /// или встаёт на рассмотрение. Возвращает количество добавленных меток.
    @discardableResult
    static func applyPeriodTags(to transaction: Transaction, allTags: [TransactionTag]) -> Int {
        var added = 0
        for tag in allTags {
            guard let period = days(from: tag.startDate, to: tag.endDate),
                  period.contains(transaction.date) else {
                // Дату сменили, и операция ушла из поездки — решать по ней больше нечего.
                transaction.setTagPending(tag.name, false)
                continue
            }
            guard !transaction.hasTag(tag.name),
                  !transaction.isTagManuallyExcluded(tag.name) else { continue }

            switch decision(for: transaction, tag: tag) {
            case .tag:
                transaction.addTag(tag.name)
                transaction.setTagPending(tag.name, false)
                added += 1
            case .review:
                transaction.setTagPending(tag.name, true)
            case .skip:
                break
            }
        }
        return added
    }

    /// То же для пачки операций (например, после импорта).
    /// Возвращает количество операций, которым добавилась хотя бы одна метка.
    @discardableResult
    static func applyPeriodTags(to transactions: [Transaction], context: ModelContext) -> Int {
        let tags = ((try? context.fetch(FetchDescriptor<TransactionTag>())) ?? [])
            .filter { $0.startDate != nil && $0.endDate != nil }
        guard !tags.isEmpty else { return 0 }
        return transactions.filter { applyPeriodTags(to: $0, allTags: tags) > 0 }.count
    }

    /// Убирает копии меток с одинаковым именем (например, от двойного касания).
    /// Операции ссылаются на метку по имени, поэтому лишняя копия просто удаляется.
    static func removeDuplicates(context: ModelContext) {
        let byAge = FetchDescriptor<TransactionTag>(sortBy: [SortDescriptor(\.createdAt)])
        guard let tags = try? context.fetch(byAge) else { return }

        var names = Set<String>()
        var changed = false
        for tag in tags where !names.insert(tag.name).inserted {
            context.delete(tag)
            changed = true
        }
        if changed {
            try? context.save()
        }
    }
}
