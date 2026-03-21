//
//  ExpenseListByCategoryView.swift
//  Finances
//
//  Created by Андрей Матиенко on 19.03.2026.
//


import SwiftUI
import SwiftData

struct ExpenseListByCategoryView: View {
    let categoryTitle: String

    @Query(sort: \Expense.date, order: .reverse)
    private var expenses: [Expense]

    private var categoryExpenses: [Expense] {
        expenses.filter { expense in
            let title = expense.categoryName ?? "Без категории"
            return title == categoryTitle
        }
    }

    var body: some View {
        List {
            ForEach(categoryExpenses) { expense in
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
        .navigationTitle(categoryTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
