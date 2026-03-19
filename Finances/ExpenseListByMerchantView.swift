//
//  ExpenseListByMerchantView.swift
//  Finances
//
//  Created by Андрей Матиенко on 19.03.2026.
//


import SwiftUI
import SwiftData

struct ExpenseListByMerchantView: View {
    let merchantTitle: String

    @Query(sort: \Expense.date, order: .reverse)
    private var expenses: [Expense]

    private var merchantExpenses: [Expense] {
        expenses.filter { expense in
            normalizedMerchantName(expense.details) == merchantTitle
        }
    }

    var body: some View {
        List {
            ForEach(merchantExpenses) { expense in
                NavigationLink {
                    ExpenseDetailView(expense: expense)
                } label: {
                    ExpenseRowView(expense: expense)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle(merchantTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func normalizedMerchantName(_ details: String) -> String {
        let uppercased = details.uppercased()

        if uppercased.hasPrefix("GRAB ") {
            return "GRAB"
        }

        if uppercased.hasPrefix("PAYOO MCDONALDS") {
            return "PAYOO MCDONALDS"
        }

        if uppercased.hasPrefix("OPENAI CHATGPT SUBSCR") {
            return "OPENAI CHATGPT SUBSCR"
        }

        if uppercased.hasPrefix("APPLE.COM BILL") {
            return "APPLE.COM BILL"
        }

        if uppercased.hasPrefix("VNPAY 43 FACTORY") {
            return "VNPAY 43 FACTORY"
        }

        if uppercased.hasPrefix("VNPAY XLIII COFFEE") {
            return "VNPAY XLIII COFFEE"
        }

        return uppercased
    }
}