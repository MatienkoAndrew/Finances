//
//  ExpenseCategoryGuesser.swift
//  Finances
//
//  Created by Андрей Матиенко on 19.03.2026.
//


import Foundation

enum ExpenseCategoryGuesser {
    static func guessCategory(for operationType: String, details: String) -> ExpenseCategory? {
        let text = details.uppercased()

        if operationType == "Снятие" {
            return .cashWithdrawal
        }

        if operationType == "Перевод" {
            return .transfer
        }

        if operationType == "Пополнение" {
            return nil
        }

        if text.contains("CHATGPT") || text.contains("SPOTIFY") || text.contains("APPLE.COM BILL") {
            return .subscription
        }

        if text.contains("GRAB") {
            return .transport
        }

        if text.contains("COFFEE") || text.contains("HIGHLANDS") || text.contains("STARBUCKS") {
            return .coffee
        }

        if text.contains("MCDONALDS")
            || text.contains("PHO")
            || text.contains("PAPASTEAK")
            || text.contains("BRUNCH")
            || text.contains("BURGERS")
            || text.contains("CUISINE")
            || text.contains("ROASTERY")
            || text.contains("BANH XEO")
            || text.contains("SECTION 30")
            || text.contains("LAVA 79")
            || text.contains("43 FACTORY")
            || text.contains("BIKINIBOTTOM") {
            return .food
        }

        if text.contains("MART")
            || text.contains("MARKET")
            || text.contains("AAUMINIMART")
            || text.contains("4BMART")
            || text.contains("GOOD MART")
            || text.contains("FULL MARKET")
            || text.contains("CJ MART")
            || text.contains("HEREMART")
            || text.contains("TONY MART") {
            return .groceries
        }

        if text.contains("AGODA") || text.contains("HOTEL") || text.contains("INN") {
            return .travel
        }

        if text.contains("MOBIFIT")
            || text.contains("FITNESS") {
            return .health
        }

        if text.contains("CAP TREO")
            || text.contains("NAM THANH")
            || text.contains("MOONMILK")
            || text.contains("NEWYORK")
            || text.contains("ELEMENT") {
            return .shopping
        }

        return nil
    }
}