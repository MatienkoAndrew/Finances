import SwiftUI
import SwiftData

/// Поиск и удаление уже сохранённых дублей (см. `DuplicateCleaner`).
///
/// По умолчанию дубли удаляются автоматически после каждого импорта, а этот экран —
/// для тех, кто хочет посмотреть сам: переключатель, ручной разбор и восстановление.
struct DuplicatesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var transactions: [Transaction]
    @Query private var accounts: [Account]

    @AppStorage(DuplicateCleaner.autoCleanupKey) private var isAutoCleanupEnabled = true

    @State private var groups: [StoredDuplicateGroup] = []
    @State private var keepSelection: [String: PersistentIdentifier] = [:]
    @State private var removedCount = 0
    @State private var isScanning = true
    @State private var isConfirmingDeleteAll = false
    @State private var errorMessage: String?

    private var extraCount: Int {
        groups.reduce(0) { $0 + $1.members.count - 1 }
    }

    var body: some View {
        List {
            settingsSection

            if isScanning {
                HStack {
                    ProgressView()
                    Text("Ищем дубли…")
                        .foregroundStyle(.secondary)
                }
            } else if groups.isEmpty {
                ContentUnavailableView(
                    "Дублей не найдено",
                    systemImage: "checkmark.circle",
                    description: Text("Одинаковых операций из разных импортов и задвоенных записей нет.")
                )
            } else {
                summarySection

                ForEach(groups) { group in
                    groupSection(group)
                }
            }
        }
        .navigationTitle("Дубли")
        .onAppear {
            // И при первом открытии, и при возврате с «Недавно удалённых».
            scan()
        }
        .onChange(of: isAutoCleanupEnabled) { _, isEnabled in
            if isEnabled, !groups.isEmpty {
                deleteExtras(in: groups)
            }
        }
        .confirmationDialog(
            "Удалить \(extraCount) \(DuplicateFormat.pluralOperations(extraCount))?",
            isPresented: $isConfirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                deleteExtras(in: groups)
            }
        } message: {
            Text("В каждой группе останется отмеченная операция. Метки, заметка и выбранная вручную категория удалённых копий перенесутся в неё.")
        }
        .alert(
            "Не удалось удалить",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var settingsSection: some View {
        Section {
            Toggle("Удалять автоматически", isOn: $isAutoCleanupEnabled)

            NavigationLink {
                RemovedDuplicatesView()
            } label: {
                HStack {
                    Text("Недавно удалённые")
                    Spacer()
                    if removedCount > 0 {
                        Text("\(removedCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            Text(isAutoCleanupEnabled
                 ? "После каждого импорта дубли удаляются сами. Всё удалённое можно вернуть в «Недавно удалённых»."
                 : "Автоочистка выключена — найденные дубли можно разобрать вручную ниже.")
        }
    }

    private var summarySection: some View {
        Section {
            Text("Групп: \(groups.count), лишних операций: \(extraCount)")

            Button(role: .destructive) {
                isConfirmingDeleteAll = true
            } label: {
                Label("Удалить все лишние", systemImage: "trash")
            }
        } footer: {
            Text("В каждой группе отмечена операция, которая останется. Нажми на другую, чтобы оставить её.")
        }
    }

    private func groupSection(_ group: StoredDuplicateGroup) -> some View {
        let keep = keepSelection[group.id] ?? group.suggestedKeep

        return Section {
            ForEach(group.members) { transaction in
                Button {
                    keepSelection[group.id] = transaction.persistentModelID
                } label: {
                    memberRow(transaction, isKept: transaction.persistentModelID == keep)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Button("Удалить лишние", role: .destructive) {
                    deleteExtras(in: [group])
                }

                Spacer()

                Button("Не дубль") {
                    DuplicateCleaner.markNotDuplicate(group)
                    groups.removeAll { $0.id == group.id }
                }
            }
            .buttonStyle(.borderless)
        } header: {
            Text(DuplicateFormat.header(date: group.members[0].date, details: group.members[0].details))
        } footer: {
            Text(footerText(for: group))
        }
    }

    private func memberRow(_ transaction: Transaction, isKept: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isKept ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isKept ? Color.green : Color.secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(DuplicateFormat.amount(transaction.amount, currency: transaction.currencyCode, kind: transaction.kind))
                    .font(.body.monospacedDigit())

                ForEach(detailLines(for: transaction), id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(isKept ? "Оставить" : "Удалить")
                .font(.caption)
                .foregroundStyle(isKept ? Color.green : Color.red)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func scan() {
        groups = DuplicateCleaner.findGroups(in: transactions, accounts: accounts)
        keepSelection = keepSelection.filter { entry in groups.contains { $0.id == entry.key } }
        removedCount = DuplicateRemovalLog.load().count
        isScanning = false
    }

    private func deleteExtras(in selectedGroups: [StoredDuplicateGroup]) {
        let removed = DuplicateCleaner.removeExtras(
            in: selectedGroups,
            keeping: keepSelection,
            automatic: false,
            context: modelContext
        )

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            DuplicateRemovalLog.remove(removed)
            errorMessage = error.localizedDescription
            return
        }

        // Не пересканировать: `@Query` может ещё держать удалённые объекты.
        // Группы не пересекаются, поэтому достаточно убрать обработанные.
        let processed = Set(selectedGroups.map(\.id))
        groups.removeAll { processed.contains($0.id) }
        removedCount += removed.count
    }

    // MARK: - Formatting

    private func footerText(for group: StoredDuplicateGroup) -> String {
        switch group.reason {
        case .exactCopy:
            return "Одна и та же запись несколько раз — например, после восстановления из резервной копии."
        case .repeatedImport:
            let amounts = Set(group.members.map { Int(($0.amount * 100).rounded()) })
            if amounts.count > 1 {
                return "Одна операция из разных выписок. Суммы в тенге отличаются: в свежей выписке окончательная сумма, в старой — предварительная."
            }
            return "Одна операция из разных выписок."
        }
    }

    private func detailLines(for transaction: Transaction) -> [String] {
        var lines: [String] = []

        if let foreignAmount = transaction.foreignAmount, let foreignCurrency = transaction.foreignCurrencyCode {
            lines.append(DuplicateFormat.number(foreignAmount, currency: foreignCurrency))
        }

        lines.append(DuplicateFormat.source(
            importedAt: transaction.importedAt,
            fileName: transaction.sourceFileName,
            createdAt: transaction.createdAt
        ))

        var meta = (transaction.fromAccount ?? transaction.toAccount)?.name ?? "без счёта"
        if let category = transaction.categoryName {
            meta += " · \(category)"
        }
        if let tags = transaction.tagNames, !tags.isEmpty {
            meta += " · \(tags.joined(separator: ", "))"
        }
        lines.append(meta)

        if let note = transaction.note, !note.isEmpty {
            lines.append(note)
        }

        return lines
    }
}

/// Общее форматирование для экранов дублей.
enum DuplicateFormat {
    static func header(date: Date, details: String) -> String {
        "\(date.formatted(date: .abbreviated, time: .omitted)) · \(details)"
    }

    static func amount(_ value: Double, currency: String, kind: TransactionKind) -> String {
        let sign: String
        switch kind {
        case .expense: sign = "− "
        case .income: sign = "+ "
        case .transfer: sign = "→ "
        }
        return sign + number(value, currency: currency)
    }

    static func number(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        let number = formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        return "\(number) \(CurrencyDisplay.normalizedCode(from: currency))"
    }

    static func source(importedAt: Date?, fileName: String?, createdAt: Date) -> String {
        guard let importedAt else {
            return "Добавлена вручную \(createdAt.formatted(date: .abbreviated, time: .shortened))"
        }

        var line = "Импорт \(importedAt.formatted(date: .abbreviated, time: .shortened))"
        if let fileName {
            line += " · \(fileName)"
        }
        return line
    }

    static func pluralOperations(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "операцию" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "операции" }
        return "операций"
    }
}
