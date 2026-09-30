import SwiftUI
import SwiftData

/// Все импорты выписок с возможностью отменить любой из них.
struct ImportHistoryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var transactions: [Transaction]

    @State private var batches: [ImportBatch] = []
    @State private var batchToUndo: ImportBatch?
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if batches.isEmpty {
                ContentUnavailableView(
                    "Импортов нет",
                    systemImage: "doc.text",
                    description: Text("Здесь появятся импортированные выписки.")
                )
            } else {
                Section {
                    ForEach(batches) { batch in
                        row(batch)
                            .swipeActions {
                                Button("Отменить", role: .destructive) {
                                    batchToUndo = batch
                                }
                            }
                    }
                } footer: {
                    Text("Отмена удаляет операции, добавленные импортом, и возвращает всё, что он поменял. Проведи влево по импорту или нажми на него.")
                }
            }
        }
        .navigationTitle("История импортов")
        .onAppear {
            // Считаем один раз и дальше правим список сами: сразу после удаления
            // `@Query` может ещё держать удалённые объекты.
            batches = ImportHistory.batches(in: transactions)
        }
        .confirmationDialog(
            undoTitle,
            isPresented: Binding(
                get: { batchToUndo != nil },
                set: { if !$0 { batchToUndo = nil } }
            ),
            titleVisibility: .visible,
            presenting: batchToUndo
        ) { batch in
            Button("Отменить импорт", role: .destructive) {
                undo(batch)
            }
        } message: { batch in
            Text(undoMessage(for: batch))
        }
        .alert(
            "Импорт отменён",
            isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
        .alert(
            "Не удалось отменить импорт",
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

    private var undoTitle: String {
        guard let batch = batchToUndo else { return "" }
        return "Отменить импорт «\(batch.fileName ?? "без имени")»?"
    }

    private func row(_ batch: ImportBatch) -> some View {
        Button {
            batchToUndo = batch
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(batch.fileName ?? "Без имени файла")
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(batch.importedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(details(for: batch))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func details(for batch: ImportBatch) -> String {
        var parts = ["Операций: \(batch.transactionCount)"]

        if let first = batch.firstDate, let last = batch.lastDate {
            let range = first == last
                ? first.formatted(date: .abbreviated, time: .omitted)
                : "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))"
            parts.append(range)
        }

        if let changed = batch.record?.modifications.count, changed > 0 {
            parts.append("изменено: \(changed)")
        }

        return parts.joined(separator: " · ")
    }

    private func undoMessage(for batch: ImportBatch) -> String {
        var message = "Будет удалено операций: \(batch.transactionCount)."
        if let changed = batch.record?.modifications.count, changed > 0 {
            message += " У \(changed) уже существовавших операций вернутся прежние значения."
        }
        if batch.record == nil {
            message += " Импорт сделан до появления отмены — изменения, которые он внёс в уже существовавшие операции, не вернутся."
        }
        return message
    }

    private func undo(_ batch: ImportBatch) {
        do {
            let summary = try ImportHistory.undo(importedAt: batch.importedAt, context: modelContext)
            batches.removeAll { $0.id == batch.id }
            resultMessage = summary.message
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
