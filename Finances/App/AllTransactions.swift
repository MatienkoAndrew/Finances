//
//  AllTransactions.swift
//  Finances
//
//  Все операции приложения — одним запросом к базе.
//

import SwiftUI
import SwiftData

/// Все операции, новые сверху. Список один на всё приложение — его держит
/// `RootTabView` (через `TransactionsStore`) и раздаёт экранам через окружение.
///
/// Раньше у каждого экрана был свой `@Query` по всей таблице, и после любого
/// сохранения каждый открытый экран (список операций, аналитика, счета, метки…)
/// заново читал из базы все операции — по запросу на экран.
///
/// Экран объявляет `@AllTransactions private var transactions`.
@propertyWrapper
struct AllTransactions: DynamicProperty {
    @Environment(\.allTransactionsSnapshot) private var snapshot

    var wrappedValue: [Transaction] {
        snapshot.items
    }
}

/// Обёртка без `Equatable`: SwiftUI сравнивает её по ссылке на массив, а не
/// перебирает все операции, решая, изменилось ли окружение.
struct AllTransactionsSnapshot {
    var items: [Transaction] = []
    /// Растёт с каждым сохранением, которое затронуло операции (и правкой полей
    /// тоже) — по нему `AnalyticsIndex` понимает, что пора пересчитаться.
    var revision = 0
}

extension EnvironmentValues {
    @Entry var allTransactionsSnapshot = AllTransactionsSnapshot()

    /// Вкладка, в которой лежит экран, сейчас открыта. Скрытая вкладка может
    /// не пересчитывать тяжёлое после каждого сохранения — она сделает это,
    /// когда её откроют. По умолчанию true: экраны вне вкладок всегда на виду.
    @Entry var isTabVisible = true
}

/// Хранилище всех операций вместо `@Query` в `RootTabView`.
///
/// `@Query` после каждого сохранения заново читает из базы всю таблицу и сравнивает
/// новую выборку со старой — даже когда поменялась одна заметка или метка. Здесь
/// таблица перечитывается, только когда операции добавились или удалились.
/// Если они лишь изменились, строки и итоги и так обновятся сами: экраны читают
/// поля операций и подписаны на их изменения. Если поменялась дата, список
/// пересортируется в памяти.
@MainActor
@Observable
final class TransactionsStore {
    private(set) var items: [Transaction] = []
    /// Номер версии операций: меняется при любом сохранении, затронувшем их.
    private(set) var revision = 0

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var observer: NSObjectProtocol?
    /// Имя сущности в базе — по умолчанию это имя класса модели.
    @ObservationIgnored private let entityName = String(describing: Transaction.self)

    /// Хранилище приложения — чтобы службы брали готовый список, а не читали таблицу.
    @ObservationIgnored static weak var current: TransactionsStore?

    init(context: ModelContext) {
        self.context = context
        Self.current = self
        refetch()
        // queue: nil — уведомление обрабатывается сразу внутри save(), до следующей
        // перерисовки: экраны не увидят удалённую операцию.
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleSave(notification.userInfo ?? [:])
            }
        }
    }

    private func handleSave(_ info: [AnyHashable: Any]) {
        func identifiers(_ key: ModelContext.NotificationKey) -> [PersistentIdentifier] {
            info[key.rawValue] as? [PersistentIdentifier] ?? []
        }
        let isOurs: (PersistentIdentifier) -> Bool = { $0.entityName == self.entityName }
        let inserted = identifiers(.insertedIdentifiers).filter(isOurs)
        let deleted = identifiers(.deletedIdentifiers).filter(isOurs)
        let updated = identifiers(.updatedIdentifiers).filter(isOurs)

        // Непонятно, что изменилось (например, удаление всей таблицы при
        // восстановлении копии), — перечитываем.
        let isUnknown = info[ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue] != nil
            || (identifiers(.insertedIdentifiers).isEmpty
                && identifiers(.deletedIdentifiers).isEmpty
                && identifiers(.updatedIdentifiers).isEmpty)

        if isUnknown {
            refetch()
            revision += 1
            return
        }
        guard !inserted.isEmpty || !deleted.isEmpty || !updated.isEmpty else { return }

        // Точечное обновление: перечитать всю таблицу — это сотни миллисекунд
        // на большой истории, а сохранение обычно меняет одну-две операции.
        if applyChanges(inserted: inserted, deleted: deleted, updated: updated) {
            revision += 1
        } else {
            refetch()
            revision += 1
        }
    }

    /// Даты и идентификаторы операций в том же порядке, что `items`: чтобы найти
    /// место операции, не читать поля каждой модели (это медленно).
    @ObservationIgnored private var dates: [Date] = []
    @ObservationIgnored private var ids: [PersistentIdentifier] = []

    /// Вставляет, удаляет и переставляет только изменённые операции.
    /// false — что-то не нашлось в контексте, нужен полный перечёт.
    private func applyChanges(
        inserted: [PersistentIdentifier],
        deleted: [PersistentIdentifier],
        updated: [PersistentIdentifier]
    ) -> Bool {
        var list = items
        var listDates = dates
        var listIDs = ids

        // Изменённые операции: переставляем, только если поменялась дата.
        var moved: [Transaction] = []
        var removing = Set(deleted)
        if !updated.isEmpty {
            let positions = Dictionary(listIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            for id in updated {
                guard let position = positions[id] else { return false }
                let transaction = list[position]
                if transaction.date != listDates[position] {
                    removing.insert(id)
                    moved.append(transaction)
                }
            }
        }

        if !removing.isEmpty {
            var keep: [Int] = []
            keep.reserveCapacity(listIDs.count)
            for (position, id) in listIDs.enumerated() where !removing.contains(id) {
                keep.append(position)
            }
            list = keep.map { list[$0] }
            listDates = keep.map { listDates[$0] }
            listIDs = keep.map { listIDs[$0] }
        }

        for transaction in moved {
            Self.insert(transaction, into: &list, dates: &listDates, ids: &listIDs)
        }
        for id in inserted {
            guard let transaction: Transaction = context.registeredModel(for: id) else { return false }
            Self.insert(transaction, into: &list, dates: &listDates, ids: &listIDs)
        }

        // Только правка полей без смены дат — массив тот же, экраны обновятся
        // по ревизии и по наблюдению за полями.
        if removing.isEmpty && inserted.isEmpty { return true }

        items = list
        dates = listDates
        ids = listIDs
        return true
    }

    /// Вставка на место по дате (новые сверху) двоичным поиском.
    private static func insert(
        _ transaction: Transaction,
        into list: inout [Transaction],
        dates: inout [Date],
        ids: inout [PersistentIdentifier]
    ) {
        let date = transaction.date
        var low = 0
        var high = dates.count
        while low < high {
            let mid = (low + high) / 2
            if dates[mid] >= date {
                low = mid + 1
            } else {
                high = mid
            }
        }
        list.insert(transaction, at: low)
        dates.insert(date, at: low)
        ids.insert(transaction.persistentModelID, at: low)
    }

    func isBacked(by other: ModelContext) -> Bool {
        context === other
    }

    private func refetch() {
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let fetched = (try? context.fetch(descriptor)) ?? []
        items = fetched
        dates = fetched.map(\.date)
        ids = fetched.map(\.persistentModelID)
    }
}

/// Все операции контекста — из памяти хранилища, если это его контекст и
/// несохранённых изменений нет; иначе — чтением из базы.
///
/// Полное чтение таблицы — сотни миллисекунд на большой истории, а после импорта
/// его по очереди делали замена оплат Apple Pay, чистка дублей, сверка баланса,
/// синхронизация курсов и категоризация. Хранилище после сохранения уже
/// актуально (обновляется внутри `save()`).
@MainActor
enum AllTransactionsFetch {
    static func all(in context: ModelContext) throws -> [Transaction] {
        if let store = TransactionsStore.current, store.isBacked(by: context), !context.hasChanges {
            return store.items
        }
        return try context.fetch(FetchDescriptor<Transaction>())
    }
}
