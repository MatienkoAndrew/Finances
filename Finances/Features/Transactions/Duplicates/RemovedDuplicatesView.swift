import SwiftUI
import SwiftData

/// Удалённые дубли с возможностью вернуть любой из них.
struct RemovedDuplicatesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var accounts: [Account]

    @State private var entries: [RemovedDuplicate] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Пусто",
                    systemImage: "tray",
                    description: Text("Здесь появятся дубли, удалённые автоматически или вручную.")
                )
            } else {
                Section {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                } footer: {
                    Text("Восстановленная операция больше не будет считаться дублем. Хранятся последние 500 удалённых.")
                }
            }
        }
        .navigationTitle("Недавно удалённые")
        .onAppear {
            entries = DuplicateRemovalLog.load()
        }
        .alert(
            "Не удалось восстановить",
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

    private func row(_ entry: RemovedDuplicate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(DuplicateFormat.header(date: entry.date, details: entry.details))
                    .font(.subheadline)

                Text(DuplicateFormat.amount(
                    entry.amount,
                    currency: entry.currencyCode,
                    kind: TransactionKind(rawValue: entry.kindRaw) ?? .expense
                ))
                .font(.body.monospacedDigit())

                if let foreignAmount = entry.foreignAmount, let foreignCurrency = entry.foreignCurrencyCode {
                    caption(DuplicateFormat.number(foreignAmount, currency: foreignCurrency))
                }

                caption(DuplicateFormat.source(
                    importedAt: entry.importedAt,
                    fileName: entry.sourceFileName,
                    createdAt: entry.createdAt
                ))

                caption("\(entry.automatic ? "Удалена автоматически" : "Удалена вручную") \(entry.removedAt.formatted(date: .abbreviated, time: .shortened))")
            }

            Spacer()

            Button("Вернуть") {
                restore(entry)
            }
            .buttonStyle(.borderless)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func restore(_ entry: RemovedDuplicate) {
        do {
            try DuplicateCleaner.restore(entry, accounts: accounts, context: modelContext)
            entries.removeAll { $0.id == entry.id }
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
