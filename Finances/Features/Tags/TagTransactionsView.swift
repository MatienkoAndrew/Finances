//
//  TagTransactionsView.swift
//  Finances
//
//  Список всех транзакций, помеченных конкретной меткой.
//  Поддерживает режим редактирования: выделить несколько транзакций
//  и одной кнопкой убрать их из метки.
//

import SwiftUI
import SwiftData

struct TagTransactionsView: View {
    @Environment(\.modelContext) private var modelContext

    let tag: TransactionTag

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @State private var editMode: EditMode = .inactive
    @State private var selection: Set<PersistentIdentifier> = []

    private var taggedTransactions: [Transaction] {
        transactions.filter { $0.hasTag(tag.name) }
    }

    var body: some View {
        List(selection: $selection) {
            if taggedTransactions.isEmpty {
                ContentUnavailableView(
                    "Нет транзакций",
                    systemImage: "tag.slash",
                    description: Text("На этой метке пока нет ни одной транзакции")
                )
            } else {
                ForEach(taggedTransactions) { transaction in
                    rowContent(for: transaction)
                        .tag(transaction.persistentModelID)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .navigationTitle(tagTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Готово" : "Изменить") {
                    withAnimation {
                        if editMode.isEditing {
                            editMode = .inactive
                            selection.removeAll()
                        } else {
                            editMode = .active
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode.isEditing {
                bottomActionBar
            }
        }
    }

    // В режиме редактирования отрубаем NavigationLink, чтобы тап выделял,
    // а не открывал детали (так работает стандартный list-edit-mode iOS).
    @ViewBuilder
    private func rowContent(for transaction: Transaction) -> some View {
        if editMode.isEditing {
            TransactionRowView(transaction: transaction)
        } else {
            NavigationLink {
                TransactionDetailView(transaction: transaction)
            } label: {
                TransactionRowView(transaction: transaction)
            }
            .buttonStyle(.plain)
        }
    }

    private var tagTitle: String {
        "\(tag.displayIcon) \(tag.name)"
    }

    private var bottomActionBar: some View {
        HStack {
            Text("\(selection.count) выбрано")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive) {
                removeSelectedFromTag()
            } label: {
                Label("Убрать из метки", systemImage: "tag.slash")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func removeSelectedFromTag() {
        guard !selection.isEmpty else { return }

        let selectedIDs = selection
        for tx in taggedTransactions where selectedIDs.contains(tx.persistentModelID) {
            // manual: true — это явное действие пользователя.
            // Авто-теггер по валюте больше не вернёт эту метку на эти транзакции.
            tx.removeTag(tag.name, manual: true)
        }
        try? modelContext.save()

        withAnimation {
            selection.removeAll()
            // После удаления полезнее остаться в режиме редактирования,
            // чтобы можно было сразу отметить ещё несколько транзакций.
        }
    }
}

private extension EditMode {
    var isEditing: Bool {
        self == .active || self == .transient
    }
}
