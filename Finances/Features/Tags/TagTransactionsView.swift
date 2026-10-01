//
//  TagTransactionsView.swift
//  Finances
//
//  Список всех транзакций, помеченных конкретной меткой.
//  Выбор как в Telegram: зажми операцию — она выделится, дальше касанием
//  выбираешь другие и одной кнопкой убираешь их из метки.
//

import SwiftUI
import SwiftData

struct TagTransactionsView: View {
    @Environment(\.modelContext) private var modelContext

    let tag: TransactionTag

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @State private var isSelecting = false
    @State private var selection: Set<PersistentIdentifier> = []
    @Query private var settings: [AppSettings]
    @Query private var trackedRates: [TrackedExchangeRate]
    @State private var isEditingTag = false
    @State private var isConfirmingDelete = false
    @State private var isShowingAnalytics = false
    @State private var openedTransaction: Transaction?
    @Environment(\.dismiss) private var dismiss

    private var taggedTransactions: [Transaction] {
        transactions.filter { $0.hasTag(tag.name) }
    }

    var body: some View {
        List {
            if taggedTransactions.isEmpty {
                ContentUnavailableView(
                    "Нет транзакций",
                    systemImage: "tag.slash",
                    description: Text("На этой метке пока нет ни одной транзакции")
                )
            } else {
                if !isSelecting {
                    summaryCard
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                ForEach(taggedTransactions) { transaction in
                    row(for: transaction)
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            selection.contains(transaction.persistentModelID)
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                        )
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(isSelecting ? "Выбрано: \(selection.count)" : tag.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelecting)
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена", action: endSelection)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isEditingTag = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Настройки метки")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                bottomActionBar
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .navigationDestination(item: $openedTransaction) { transaction in
            TransactionDetailView(transaction: transaction)
        }
        .navigationDestination(isPresented: $isShowingAnalytics) {
            AnalyticsView(focusedTag: tag)
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

    /// Итог по метке: сколько потрачено, сколько операций, период — и вход в аналитику.
    private var summaryCard: some View {
        let stats = TagStats.make(tags: [tag], transactions: taggedTransactions, settings: settings.first, trackedRates: trackedRates)[tag.persistentModelID] ?? .empty
        let color = tag.colorHex.flatMap { Color(hex: $0) } ?? .accentColor

        return HStack(spacing: 14) {
            TagIconView(icon: tag.icon, colorHex: tag.colorHex, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(TagFormatting.rub(stats.spentRub))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(TagFormatting.operations(stats.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let period = TagFormatting.period(of: tag) {
                    Text(period)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Spacer(minLength: 8)

            Button {
                isShowingAnalytics = true
            } label: {
                Text("Аналитика")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [Color.blue.opacity(0.75), Color.blue], startPoint: .leading, endPoint: .trailing),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .fixedSize()
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

    // MARK: - Rows

    /// Касание открывает операцию, а в режиме выбора — отмечает её.
    /// Долгое нажатие включает режим выбора с этой операцией.
    private func row(for transaction: Transaction) -> some View {
        let id = transaction.persistentModelID
        let isSelected = selection.contains(id)

        return HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // В режиме выбора плашка категории не открывается — касание отмечает операцию.
            TransactionRowView(transaction: transaction)
                .allowsHitTesting(!isSelecting)

            if !isSelecting {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                toggle(id)
            } else {
                openedTransaction = transaction
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            guard !isSelecting else { return toggle(id) }
            withAnimation(.snappy(duration: 0.25)) {
                isSelecting = true
                selection = [id]
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: isSelecting ? (isSelected ? "Снять выбор" : "Выбрать") : "Выбрать несколько") {
            if isSelecting {
                toggle(id)
            } else {
                withAnimation { isSelecting = true; selection = [id] }
            }
        }
    }

    /// Сняли выбор с последней операции — режим выбора закрывается, как в Telegram.
    private func toggle(_ id: PersistentIdentifier) {
        withAnimation(.snappy(duration: 0.2)) {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
            if selection.isEmpty {
                isSelecting = false
            }
        }
    }

    private func endSelection() {
        withAnimation(.snappy(duration: 0.25)) {
            isSelecting = false
            selection.removeAll()
        }
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
            // manual: true — это явное действие пользователя:
            // метка по датам больше не вернётся на эти операции.
            tx.removeTag(tag.name, manual: true)
        }
        try? modelContext.save()
        endSelection()
    }
}
