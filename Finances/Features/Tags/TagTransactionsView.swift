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
    @Query private var settings: [AppSettings]
    @Query private var trackedRates: [TrackedExchangeRate]
    @State private var isEditingTag = false
    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss

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
                if !editMode.isEditing {
                    summaryCard
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

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
                if !editMode.isEditing {
                    Button {
                        isEditingTag = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Изменить метку")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Готово" : "Выбрать") {
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
        .sheet(isPresented: $isEditingTag) {
            TagEditorSheet(tag: tag) { _ in isConfirmingDelete = true }
        }
        .confirmationDialog(
            "Удалить метку «\(tag.name)»?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive, action: deleteTag)
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Метка снимется с операций, сами операции останутся.")
        }
    }

    /// Итог по метке: сколько операций и сколько потрачено.
    private var summaryCard: some View {
        let stats = TagStats.make(tags: [tag], transactions: taggedTransactions, settings: settings.first, trackedRates: trackedRates)[tag.persistentModelID] ?? .empty
        let color = tag.colorHex.flatMap { Color(hex: $0) } ?? .accentColor

        return HStack(spacing: 14) {
            TagIconView(icon: tag.icon, colorHex: tag.colorHex, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(TagFormatting.rub(stats.spentRub))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text([TagFormatting.operations(stats.count), TagFormatting.period(of: tag)].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.16), color.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private func deleteTag() {
        for transaction in transactions where transaction.hasTag(tag.name) {
            transaction.removeTag(tag.name)
        }
        modelContext.delete(tag)
        try? modelContext.save()
        dismiss()
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
        tag.name
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
