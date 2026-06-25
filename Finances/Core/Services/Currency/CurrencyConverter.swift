//
//  CurrencyConverter.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import Foundation

enum CurrencyConverter {
    static func kztToRub(_ amountKZT: Double, kztPerRub: Double) -> Double {
        guard kztPerRub > 0 else { return 0 }
        return amountKZT / kztPerRub
    }
}