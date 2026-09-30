import Foundation
import SwiftData

@Model
final class Transaction {
    var date: Date

    var kindRaw: String

    /// Что ушло с исходного счета.
    /// Для expense — сумма расхода.
    /// Для income — обычно равна зачисленной сумме.
    /// Для transfer — сумма списания с source account.
    var amount: Double
    var currencyCode: String

    /// Что пришло на целевой счет.
    /// Нужна в первую очередь для transfer между разными валютами.
    /// Для обычного same-currency transfer можно хранить такую же сумму.
    var toAmount: Double?
    var toCurrencyCode: String?

    var details: String

    /// Дополнительная сумма в "внешней" валюте:
    /// например, покупка по карте в VND, а списание в KZT.
    var foreignAmount: Double?
    var foreignCurrencyCode: String?

    var rubAmount: Double?

    var categoryName: String?

    /// Подкатегория внутри `categoryName` (например, «Кофе» внутри «Еда»).
    /// Optional, чтобы не ломать существующие данные SwiftData при миграции —
    /// старые транзакции получат `nil`.
    var subcategoryName: String?

    /// Признак того, что категория была установлена пользователем вручную.
    /// Если `true`, массовая авто-категоризация (применение правил) обязана
    /// пропускать такую транзакцию, чтобы не затереть ручной выбор.
    /// Хранится как Optional, чтобы при добавлении поля не ломать
    /// существующие данные SwiftData (старые транзакции получат `nil`).
    var isCategoryManuallySet: Bool? = false

    var note: String?
    
    /// Метки для группировки транзакций (страны, проекты и т.д.)
    var tagNames: [String]?

    /// Список меток, которые пользователь ЯВНО снял с этой транзакции вручную.
    /// Авто-теггер обязан пропускать такие имена, иначе при следующем
    /// сохранении транзакции метка снова будет навешена и ручное снятие сотрётся.
    /// Optional — чтобы старые транзакции в SwiftData не сломались при миграции.
    var manuallyExcludedTagNames: [String]?

    var fingerprint: String?
    var sourceFileName: String?
    var importedAt: Date?

    var createdAt: Date

    var fromAccount: Account?
    var toAccount: Account?

    init(
        date: Date,
        kindRaw: String,
        amount: Double,
        currencyCode: String,
        toAmount: Double? = nil,
        toCurrencyCode: String? = nil,
        details: String,
        foreignAmount: Double? = nil,
        foreignCurrencyCode: String? = nil,
        rubAmount: Double? = nil,
        categoryName: String? = nil,
        subcategoryName: String? = nil,
        isCategoryManuallySet: Bool? = false,
        note: String? = nil,
        tagNames: [String]? = nil,
        manuallyExcludedTagNames: [String]? = nil,
        fingerprint: String? = nil,
        sourceFileName: String? = nil,
        importedAt: Date? = nil,
        createdAt: Date = Date(),
        fromAccount: Account? = nil,
        toAccount: Account? = nil
    ) {
        self.date = date
        self.kindRaw = kindRaw
        self.amount = amount
        self.currencyCode = currencyCode
        self.toAmount = toAmount
        self.toCurrencyCode = toCurrencyCode
        self.details = details
        self.foreignAmount = foreignAmount
        self.foreignCurrencyCode = foreignCurrencyCode
        self.rubAmount = rubAmount
        self.categoryName = categoryName
        self.subcategoryName = subcategoryName
        self.isCategoryManuallySet = isCategoryManuallySet
        self.note = note
        self.tagNames = tagNames
        self.manuallyExcludedTagNames = manuallyExcludedTagNames
        self.fingerprint = fingerprint
        self.sourceFileName = sourceFileName
        self.importedAt = importedAt
        self.createdAt = createdAt
        self.fromAccount = fromAccount
        self.toAccount = toAccount
    }
}

extension Transaction {
    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    /// Пометка, которую импорт ставит строкам «Курсовая разница» из выписки Kaspi.
    static let exchangeRateDifferenceNote = "Курсовая разница"

    var isExchangeRateDifference: Bool {
        note == Self.exchangeRateDifferenceNote
    }

    /// Курсовая разница «в плюс» — Kaspi вернул часть уже списанной суммы покупки.
    /// Это не доход: в аналитике она уменьшает расходы в своей категории и у своего мерчанта.
    var reducesExpensesInAnalytics: Bool {
        kind == .income && isExchangeRateDifference
    }

    var countsAsExpenseInAnalytics: Bool {
        kind == .expense || reducesExpensesInAnalytics
    }

    var countsAsIncomeInAnalytics: Bool {
        kind == .income && !reducesExpensesInAnalytics
    }

    /// Вклад в расходы или доходы: у курсовой разницы «в плюс» — отрицательный вклад в расходы.
    var analyticsAmount: Double {
        switch kind {
        case .expense:
            return amount
        case .income:
            return reducesExpensesInAnalytics ? -amount : amount
        case .transfer:
            return 0
        }
    }

    var creditedAmount: Double {
        toAmount ?? amount
    }

    var creditedCurrencyCode: String {
        toCurrencyCode ?? currencyCode
    }

    var isCrossCurrencyTransfer: Bool {
        kind == .transfer && creditedCurrencyCode != currencyCode
    }
    
    // MARK: - Tags

    /// Добавить метку к транзакции.
    /// Если пользователь явно проставляет метку вручную (`manual: true`),
    /// мы дополнительно убираем её из «чёрного списка» авто-исключений,
    /// так как явное добавление = повторное согласие с этой меткой.
    func addTag(_ tagName: String, manual: Bool = false) {
        if tagNames == nil {
            tagNames = []
        }
        if !tagNames!.contains(tagName) {
            tagNames!.append(tagName)
        }
        if manual {
            manuallyExcludedTagNames?.removeAll { $0 == tagName }
            if manuallyExcludedTagNames?.isEmpty == true {
                manuallyExcludedTagNames = nil
            }
        }
    }

    /// Удалить метку из транзакции.
    /// Если удаление инициировано пользователем (`manual: true`),
    /// запоминаем имя метки в `manuallyExcludedTagNames`, чтобы авто-теггер
    /// больше не возвращал её на эту транзакцию.
    func removeTag(_ tagName: String, manual: Bool = false) {
        tagNames?.removeAll { $0 == tagName }
        if tagNames?.isEmpty == true {
            tagNames = nil
        }
        if manual {
            if manuallyExcludedTagNames == nil {
                manuallyExcludedTagNames = []
            }
            if !manuallyExcludedTagNames!.contains(tagName) {
                manuallyExcludedTagNames!.append(tagName)
            }
        }
    }

    /// Проверить, есть ли метка
    func hasTag(_ tagName: String) -> Bool {
        tagNames?.contains(tagName) == true
    }

    /// Снимал ли пользователь эту метку вручную раньше.
    func isTagManuallyExcluded(_ tagName: String) -> Bool {
        manuallyExcludedTagNames?.contains(tagName) == true
    }
}

enum TransactionKind: String, CaseIterable, Identifiable {
    case expense
    case income
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: return "Расход"
        case .income: return "Доход"
        case .transfer: return "Перевод"
        }
    }

    var systemImage: String {
        switch self {
        case .expense: return "arrow.up.circle.fill"
        case .income: return "arrow.down.circle.fill"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        }
    }
}
