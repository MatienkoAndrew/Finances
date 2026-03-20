import SwiftUI
import SwiftData

struct ExpenseListByCashFlowView: View {
    let flowType: CashFlowType
    let scope: AnalyticsScope

    @Query(sort: \Expense.date, order: .reverse)
    private var expenses: [Expense]

    private var filteredExpenses: [Expense] {
        expenses.filter {
            flowType.matches($0) && scope.contains($0.date)
        }
    }

    var body: some View {
        List {
            ForEach(filteredExpenses) { expense in
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
        .navigationTitle("\(flowType.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            HStack {
                Text(scope.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(filteredExpenses.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }
}
