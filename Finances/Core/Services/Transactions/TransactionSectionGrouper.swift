//
//  TransactionSectionGrouper.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import Foundation

enum TransactionSectionGrouper {
    typealias DaySection = (date: Date, items: [Transaction])

    /// Операции по дням, новые сверху, — не больше `limit` дней.
    /// `hasMore` — остались ли дни сверх лимита (список подгрузит их при прокрутке).
    ///
    /// Операции обычно уже отсортированы по дате (новые сверху) — тогда хватает
    /// одного прохода до нужного дня, без разбора всей истории. Если порядок
    /// другой, группируем всё целиком.
    static func groupedByDay(_ transactions: [Transaction], limit: Int = .max) -> (sections: [DaySection], hasMore: Bool) {
        let calendar = Calendar.current
        var sections: [DaySection] = []
        var currentDay: Date?
        var currentItems: [Transaction] = []

        for (index, transaction) in transactions.enumerated() {
            if let day = currentDay, transaction.date >= day {
                guard calendar.isDate(transaction.date, inSameDayAs: day) else {
                    // Более поздний день после раннего — порядок не по дате.
                    return groupedByDayUnsorted(transactions, limit: limit)
                }
                currentItems.append(transaction)
                continue
            }

            if let day = currentDay {
                sections.append((day, sortedWithinDay(currentItems)))
                if sections.count == limit {
                    return (sections, index < transactions.count)
                }
            }
            currentDay = calendar.startOfDay(for: transaction.date)
            currentItems = [transaction]
        }

        if let day = currentDay {
            sections.append((day, sortedWithinDay(currentItems)))
        }
        return (sections, false)
    }

    private static func groupedByDayUnsorted(_ transactions: [Transaction], limit: Int) -> (sections: [DaySection], hasMore: Bool) {
        let grouped = Dictionary(grouping: transactions) {
            Calendar.current.startOfDay(for: $0.date)
        }
        let all = grouped
            .map { key, value in (date: key, items: sortedWithinDay(value)) }
            .sorted { $0.date > $1.date }
        return (Array(all.prefix(limit)), all.count > limit)
    }

    /// Внутри дня — по времени, при равном времени — добавленные позже выше.
    private static func sortedWithinDay(_ items: [Transaction]) -> [Transaction] {
        items.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}
