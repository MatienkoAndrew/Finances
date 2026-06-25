//
//  TransactionSectionGrouper.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import Foundation

enum TransactionSectionGrouper {
    static func groupedByDay(_ transactions: [Transaction]) -> [(date: Date, items: [Transaction])] {
        let grouped = Dictionary(grouping: transactions) {
            Calendar.current.startOfDay(for: $0.date)
        }

        return grouped
            .map { key, value in
                let sortedItems = value.sorted { lhs, rhs in
                    if lhs.date != rhs.date {
                        return lhs.date > rhs.date
                    }
                    return lhs.createdAt > rhs.createdAt
                }
                return (date: key, items: sortedItems)
            }
            .sorted { $0.date > $1.date }
    }
}