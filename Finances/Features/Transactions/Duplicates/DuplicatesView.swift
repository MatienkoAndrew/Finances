import SwiftUI
import SwiftData

/// Поиск и удаление уже сохранённых дублей (см. `DuplicateDetector`).
struct DuplicatesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var transactions: [Transaction]
    @Query private var accounts: [Account]

    /// Группы, которые пользователь отметил «Не дубль», — по подписи группы.
    @AppStorage("duplicates_ignored_groups") private var ignoredGroupsRaw = ""

    @State private var groups: [DuplicateSet] = []
    @State private var keepSelection: [String: PersistentIdentifier] = [:]
    @State private var isScanning = true
    @State private var isConfirmingDeleteAll = false
    @State private var errorMessage: String?

    struct DuplicateSet: Identifiable {
        /// Подпись группы — стабильна между запусками, нужна для «Не дубль».
        let id: String
        let reason: DuplicateGroup.Reason
        let members: [Transaction]
        let suggestedKeep: PersistentIdentifier
    }

    private var ignoredGroups: Set<String> {
        Set(ignoredGroupsRaw.split(separator: "\n").map(String.init))
    }

    private var extraCount: Int {
        groups.reduce(0) { $0 + $1.members.count - 1 }
    }

    var body: some View {
        List {
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
        .task {
            scan()
        }
        .confirmationDialog(
            "Удалить \(extraCount) \(pluralOperations(extraCount))?",
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

    private var summarySection: some View {
        Section {
            Text("Групп: \(groups.count), лишних операций: \(extraCount)")

            Button(role: .destructive) {
                isConfirmingDeleteAll = true
            } label: {
                Label("Удалить все лишние", systemImage: "trash")
            }
        } footer: {
            Text("В каждой группе отмечена операция, которая останется. Нажми на другую, чтобы оставить её. Перед удалением можно сделать резервную копию в настройках.")
        }
    }

    private func groupSection(_ group: DuplicateSet) -> some View {
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
                    ignore(group)
                }
            }
            .buttonStyle(.borderless)
        } header: {
            Text(headerText(for: group))
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
                Text(amountText(for: transaction))
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
        let kaspiAccount = AccountLookup.kaspi(in: accounts)
        let snapshot = transactions

        let candidates = snapshot.map { transaction in
            DuplicateCandidate(
                snapshot: PDFImporter.snapshot(of: transaction, kaspiAccount: kaspiAccount),
                fingerprint: transaction.fingerprint,
                createdAt: transaction.createdAt,
                importedAt: transaction.importedAt,
                hasAccount: transaction.fromAccount != nil || transaction.toAccount != nil
            )
        }

        let ignored = ignoredGroups

        groups = DuplicateDetector.findGroups(in: candidates).compactMap { found in
            let members = found.memberIndices.map { snapshot[$0] }
            let id = signature(of: members)
            guard !ignored.contains(id) else { return nil }

            return DuplicateSet(
                id: id,
                reason: found.reason,
                members: members,
                suggestedKeep: snapshot[found.keepIndex].persistentModelID
            )
        }

        keepSelection = keepSelection.filter { entry in groups.contains { $0.id == entry.key } }
        isScanning = false
    }

    private func deleteExtras(in selectedGroups: [DuplicateSet]) {
        for group in selectedGroups {
            let keepID = keepSelection[group.id] ?? group.suggestedKeep
            guard let keep = group.members.first(where: { $0.persistentModelID == keepID }) else { continue }

            for duplicate in group.members where duplicate.persistentModelID != keepID {
                mergeUserData(from: duplicate, into: keep)
                modelContext.delete(duplicate)
            }
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            return
        }

        // Не пересканировать: `@Query` может ещё держать удалённые объекты.
        // Группы не пересекаются, поэтому достаточно убрать обработанные.
        let processed = Set(selectedGroups.map(\.id))
        groups.removeAll { processed.contains($0.id) }
    }

    /// Не терять то, что пользователь проставил руками на удаляемой копии.
    private func mergeUserData(from duplicate: Transaction, into keep: Transaction) {
        let tags = (keep.tagNames ?? []) + (duplicate.tagNames ?? []).filter { !(keep.tagNames ?? []).contains($0) }
        if !tags.isEmpty {
            keep.tagNames = tags
        }

        if (keep.note ?? "").isEmpty, let note = duplicate.note, !note.isEmpty {
            keep.note = note
        }

        let duplicateHasManualCategory = duplicate.isCategoryManuallySet == true && duplicate.categoryName != nil
        if (duplicateHasManualCategory && keep.isCategoryManuallySet != true)
            || (keep.categoryName == nil && duplicate.categoryName != nil) {
            keep.categoryName = duplicate.categoryName
            keep.subcategoryName = duplicate.subcategoryName
            keep.isCategoryManuallySet = duplicate.isCategoryManuallySet
        }
    }

    private func ignore(_ group: DuplicateSet) {
        ignoredGroupsRaw = (ignoredGroups.union([group.id])).sorted().joined(separator: "\n")
        groups.removeAll { $0.id == group.id }
    }

    // MARK: - Formatting

    private func signature(of members: [Transaction]) -> String {
        members
            .map { transaction in
                [
                    transaction.fingerprint ?? "-",
                    "\(transaction.createdAt.timeIntervalSinceReferenceDate)",
                    "\(transaction.date.timeIntervalSinceReferenceDate)",
                    transaction.details
                ].joined(separator: "|")
            }
            .sorted()
            .joined(separator: ";")
    }

    private func headerText(for group: DuplicateSet) -> String {
        let first = group.members[0]
        return "\(first.date.formatted(date: .abbreviated, time: .omitted)) · \(first.details)"
    }

    private func footerText(for group: DuplicateSet) -> String {
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

    private func amountText(for transaction: Transaction) -> String {
        let sign: String
        switch transaction.kind {
        case .expense: sign = "− "
        case .income: sign = "+ "
        case .transfer: sign = "→ "
        }

        return sign + formatted(transaction.amount, currency: transaction.currencyCode)
    }

    private func detailLines(for transaction: Transaction) -> [String] {
        var lines: [String] = []

        if let foreignAmount = transaction.foreignAmount, let foreignCurrency = transaction.foreignCurrencyCode {
            lines.append(formatted(foreignAmount, currency: foreignCurrency))
        }

        if let importedAt = transaction.importedAt {
            var line = "Импорт \(importedAt.formatted(date: .abbreviated, time: .shortened))"
            if let fileName = transaction.sourceFileName {
                line += " · \(fileName)"
            }
            lines.append(line)
        } else {
            lines.append("Добавлена вручную \(transaction.createdAt.formatted(date: .abbreviated, time: .shortened))")
        }

        let account = (transaction.fromAccount ?? transaction.toAccount)?.name ?? "без счёта"
        var meta = account
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

    private func formatted(_ value: Double, currency: String) -> String {
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

    private func pluralOperations(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "операцию" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "операции" }
        return "операций"
    }
}
