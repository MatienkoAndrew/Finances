//
//  AnalyticsScope.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import Foundation

struct AnalyticsScope {
    let title: String
    let contains: (Date) -> Bool
}