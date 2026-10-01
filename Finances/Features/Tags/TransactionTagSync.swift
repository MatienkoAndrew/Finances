//
//  TransactionTagSync.swift
//  Finances
//
//  Метки по датам: метка с периодом стоит на всех операциях за эти дни.
//  Был в Корее с 12 по 29 сентября — все операции за эти даты получают
//  «Южную Корею», в какой бы валюте ни платил. Новые операции за эти дни
//  (добавленные вручную или из выписки) получают метку сами.
//  Если пользователь снял метку с операции вручную, она не возвращается.
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

    /// Метку сохранили в редакторе: ставим её на все операции за период,
    /// а с дней, которые выпали из старого периода, снимаем.
    static func applyPeriod(
        of tag: TransactionTag,
        previousStart: Date?,
        previousEnd: Date?,
        transactions: [Transaction]
    ) {
        let current = days(from: tag.startDate, to: tag.endDate)
        let previous = days(from: previousStart, to: previousEnd)
        guard current != nil || previous != nil else { return }

        for transaction in transactions {
            if let current, current.contains(transaction.date) {
                if !transaction.isTagManuallyExcluded(tag.name) {
                    transaction.addTag(tag.name)
                }
            } else if let previous, previous.contains(transaction.date) {
                transaction.removeTag(tag.name)
            }
        }
    }

    /// Новая или изменённая операция получает метки, в период которых попала.
    /// Возвращает количество добавленных меток.
    @discardableResult
    static func applyPeriodTags(to transaction: Transaction, allTags: [TransactionTag]) -> Int {
        var added = 0
        for tag in allTags {
            guard let period = days(from: tag.startDate, to: tag.endDate),
                  period.contains(transaction.date),
                  !transaction.hasTag(tag.name),
                  !transaction.isTagManuallyExcluded(tag.name) else { continue }
            transaction.addTag(tag.name)
            added += 1
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
