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

    /// Метки, на которые операция ждёт решения пользователя: день поездки,
    /// но заплачено не в её валюте (доллары в Японии). Optional — для миграции.
    var pendingTagNames: [String]?

    /// Метки, которые пользователь подтвердил вручную: правило валюты их не снимает.
    /// Optional — для миграции.
    var manuallyIncludedTagNames: [String]?

    var fingerprint: String?
    var sourceFileName: String?
    var importedAt: Date?

    /// Название магазина, как его передал Wallet при оплате через Apple Pay
    /// (автоматизация «Транзакция» в «Командах»). nil — операция не из Apple Pay.
    /// Optional — чтобы старые транзакции в SwiftData не сломались при миграции.
    var walletMerchant: String?

    /// Сумма оплаты текстом, как её передал Wallet («NT$79,00»). Нужна, чтобы было
    /// видно, по чему определилась валюта. Optional — старые транзакции не ломаются.
    var walletAmountText: String?

    /// Назначение операции: возврат за покупку, оплата переводом, перемещение
    /// между своими счетами (`TransactionPurpose`). nil — по виду операции.
    /// Optional — старые транзакции не ломаются при миграции.
    var purposeRaw: String? = nil

    /// Ключ покупки для связи с возвратами; заводится при первой привязке.
    var linkKey: String? = nil

    /// У возврата — `linkKey` покупки, к которой он относится.
    var refundOfLinkKey: String? = nil

    /// Пользователь отметил покупку регулярным платежом (`RecurringPeriod`):
    /// все списания того же магазина в той же валюте — одна подписка.
    /// Optional — для миграции.
    var recurringPeriodRaw: String? = nil

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
        pendingTagNames: [String]? = nil,
        manuallyIncludedTagNames: [String]? = nil,
        fingerprint: String? = nil,
        sourceFileName: String? = nil,
        importedAt: Date? = nil,
        walletMerchant: String? = nil,
        walletAmountText: String? = nil,
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
        self.pendingTagNames = pendingTagNames
        self.manuallyIncludedTagNames = manuallyIncludedTagNames
        self.fingerprint = fingerprint
        self.sourceFileName = sourceFileName
        self.importedAt = importedAt
        self.walletMerchant = walletMerchant
        self.walletAmountText = walletAmountText
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

    /// Оплата из Apple Pay, которую ещё не сверили с выпиской: описание — из Wallet,
    /// время — настоящее, сумма валютной покупки в тенге — примерная.
    /// При импорте выписки её строка заменит эту операцию.
    var isAwaitingStatement: Bool {
        walletMerchant != nil && fingerprint == nil
    }

    var purpose: TransactionPurpose? {
        get { purposeRaw.flatMap(TransactionPurpose.init(rawValue:)) }
        set { purposeRaw = newValue?.rawValue }
    }

    /// Назначения, которые можно выбрать для операции этого вида.
    var availablePurposes: [TransactionPurpose] {
        switch kind {
        case .expense: return []
        case .income: return [.refund, .ownTransfer]
        case .transfer: return [.payment, .ownTransfer]
        }
    }

    /// Возврат или компенсация за покупку — зачисление, которое уменьшает расходы.
    var isRefund: Bool {
        kind == .income && purpose == .refund && !isExchangeRateDifference
    }

    /// Перевод, которым за что-то заплатили: в аналитике это расход своей категории.
    var isTransferPayment: Bool {
        kind == .transfer && purpose == .payment
    }

    /// Перемещение между своими счетами: ни доход, ни расход.
    var isOwnAccountsMove: Bool {
        purpose == .ownTransfer
    }

    /// Покупка в аналитике: расход или оплата переводом (без курсовых разниц).
    var countsAsPurchaseInAnalytics: Bool {
        (kind == .expense || isTransferPayment) && !isExchangeRateDifference
    }

    /// Курсовая разница «в плюс» или возврат за покупку. Это не доход:
    /// в аналитике они уменьшают расходы в своей категории и у своего мерчанта.
    var reducesExpensesInAnalytics: Bool {
        kind == .income && (isExchangeRateDifference || isRefund)
    }

    var countsAsExpenseInAnalytics: Bool {
        kind == .expense || isTransferPayment || reducesExpensesInAnalytics
    }

    var countsAsIncomeInAnalytics: Bool {
        kind == .income && !reducesExpensesInAnalytics && !isOwnAccountsMove
    }

    /// Вклад в расходы или доходы: у курсовой разницы «в плюс» и возврата — отрицательный вклад в расходы.
    var analyticsAmount: Double {
        switch kind {
        case .expense:
            return amount
        case .income:
            if isOwnAccountsMove { return 0 }
            return reducesExpensesInAnalytics ? -amount : amount
        case .transfer:
            return isTransferPayment ? amount : 0
        }
    }

    /// Привязать возврат к покупке: возврат берёт её категорию, чтобы
    /// уменьшить расходы там же, где была покупка.
    func linkRefund(to purchase: Transaction) {
        if purchase.linkKey == nil {
            purchase.linkKey = UUID().uuidString
        }
        purpose = .refund
        refundOfLinkKey = purchase.linkKey
        categoryName = purchase.categoryName
        subcategoryName = purchase.subcategoryName
    }

    func unlinkRefund() {
        refundOfLinkKey = nil
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
    /// так как явное добавление = повторное согласие с этой меткой,
    /// и запоминаем выбор: правило валюты такую метку уже не снимет.
    func addTag(_ tagName: String, manual: Bool = false) {
        Self.insert(tagName, into: &tagNames)
        if manual {
            Self.remove(tagName, from: &manuallyExcludedTagNames)
            Self.remove(tagName, from: &pendingTagNames)
            Self.insert(tagName, into: &manuallyIncludedTagNames)
        }
    }

    /// Удалить метку из транзакции.
    /// Если удаление инициировано пользователем (`manual: true`),
    /// запоминаем имя метки в `manuallyExcludedTagNames`, чтобы авто-теггер
    /// больше не возвращал её на эту транзакцию.
    func removeTag(_ tagName: String, manual: Bool = false) {
        Self.remove(tagName, from: &tagNames)
        if manual {
            Self.insert(tagName, into: &manuallyExcludedTagNames)
            Self.remove(tagName, from: &pendingTagNames)
            Self.remove(tagName, from: &manuallyIncludedTagNames)
        }
    }

    /// Операция ждёт решения: относится ли она к этой метке.
    func isTagPending(_ tagName: String) -> Bool {
        pendingTagNames?.contains(tagName) == true
    }

    func setTagPending(_ tagName: String, _ isPending: Bool) {
        if isPending {
            Self.insert(tagName, into: &pendingTagNames)
        } else {
            Self.remove(tagName, from: &pendingTagNames)
        }
    }

    /// Пользователь сам подтвердил эту метку.
    func isTagManuallyIncluded(_ tagName: String) -> Bool {
        manuallyIncludedTagNames?.contains(tagName) == true
    }

    /// Метку переименовали — меняем имя во всех списках операции.
    func renameTag(_ oldName: String, to newName: String) {
        for keyPath in Self.tagLists {
            self[keyPath: keyPath] = self[keyPath: keyPath]?.map { $0 == oldName ? newName : $0 }
        }
    }

    /// Метку удалили — убираем её отовсюду.
    func forgetTag(_ tagName: String) {
        for keyPath in Self.tagLists {
            Self.remove(tagName, from: &self[keyPath: keyPath])
        }
    }

    private static let tagLists: [ReferenceWritableKeyPath<Transaction, [String]?>] = [
        \.tagNames, \.manuallyExcludedTagNames, \.pendingTagNames, \.manuallyIncludedTagNames
    ]

    private static func insert(_ name: String, into list: inout [String]?) {
        if list?.contains(name) == true { return }
        list = (list ?? []) + [name]
    }

    /// Пустой список хранится как nil — как у старых операций.
    private static func remove(_ name: String, from list: inout [String]?) {
        list?.removeAll { $0 == name }
        if list?.isEmpty == true {
            list = nil
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

/// Как часто повторяется регулярный платёж.
enum RecurringPeriod: String, CaseIterable, Identifiable {
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: return "Каждую неделю"
        case .monthly: return "Каждый месяц"
        case .yearly: return "Каждый год"
        }
    }

    var shortTitle: String {
        switch self {
        case .weekly: return "в неделю"
        case .monthly: return "в месяц"
        case .yearly: return "в год"
        }
    }

    /// Во сколько раз платёж больше или меньше месячного.
    var monthlyFactor: Double {
        switch self {
        case .weekly: return 52.0 / 12.0
        case .monthly: return 1
        case .yearly: return 1.0 / 12.0
        }
    }

    var calendarStep: (component: Calendar.Component, value: Int) {
        switch self {
        case .weekly: return (.weekOfYear, 1)
        case .monthly: return (.month, 1)
        case .yearly: return (.year, 1)
        }
    }
}

/// Зачем была операция — когда вид операции этого не говорит.
enum TransactionPurpose: String, CaseIterable, Identifiable {
    /// Зачисление — возврат или компенсация за покупку.
    case refund
    /// Исходящий перевод — оплата товара или услуги.
    case payment
    /// Перевод или зачисление между своими счетами.
    case ownTransfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .refund: return "Возврат или компенсация"
        case .payment: return "Оплата"
        case .ownTransfer: return "Между своими счетами"
        }
    }

    var systemImage: String {
        switch self {
        case .refund: return "arrow.uturn.backward.circle.fill"
        case .payment: return "cart.circle.fill"
        case .ownTransfer: return "arrow.triangle.swap"
        }
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
