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

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var observer: NSObjectProtocol?
    /// Имя сущности в базе — по умолчанию это имя класса модели.
    @ObservationIgnored private let entityName = String(describing: Transaction.self)

    init(context: ModelContext) {
        self.context = context
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
        let inserted = identifiers(.insertedIdentifiers)
        let deleted = identifiers(.deletedIdentifiers)
        let updated = identifiers(.updatedIdentifiers)

        // Непонятно, что изменилось (например, удаление всей таблицы при
        // восстановлении копии), — перечитываем.
        let isUnknown = info[ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue] != nil
            || (inserted.isEmpty && deleted.isEmpty && updated.isEmpty)
        let isOurs: (PersistentIdentifier) -> Bool = { $0.entityName == self.entityName }

        if isUnknown || inserted.contains(where: isOurs) || deleted.contains(where: isOurs) {
            refetch()
        } else if updated.contains(where: isOurs) {
            resortIfNeeded()
        }
    }

    private func refetch() {
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        items = (try? context.fetch(descriptor)) ?? []
    }

    /// Поменялась дата — операция должна встать на новое место. Иначе массив не трогаем,
    /// чтобы экраны не перестраивались зря.
    private func resortIfNeeded() {
        let isSorted = zip(items, items.dropFirst()).allSatisfy { $0.date >= $1.date }
        guard !isSorted else { return }
        items = items.sorted { $0.date > $1.date }
    }
}
