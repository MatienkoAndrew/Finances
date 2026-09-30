//
//  AnalyticsScope.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import Foundation

/// Универсальный фильтр для drill-down экранов из аналитики.
///
/// Содержит два предиката:
/// • `matches(_:)` принимает целиком `Transaction` — это основной путь и в режиме
///   меток он проверяет ещё и наличие тега, не только диапазон дат.
/// • `containsDate(_:)` остаётся для legacy-экранов на старой модели `Expense`,
///   где доступа к транзакции/тегам нет — там фильтр работает по диапазону дат.
struct AnalyticsScope {
    let title: String
    let matches: (Transaction) -> Bool
    let containsDate: (Date) -> Bool
}
