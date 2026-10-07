//
//  ApplePayExpenses.swift
//  Finances
//
//  Траты из Apple Pay. Автоматизация «Транзакция» в «Командах» после каждой
//  оплаты картой из Wallet передаёт сумму и магазин, и трата сразу появляется
//  в приложении. Позже строка выписки заменяет её точной суммой и названием из банка.
//

import Foundation
import SwiftData

enum ApplePayExpenses {
    struct Recorded {
        /// Что показать в уведомлении после оплаты.
        let message: String
    }

    enum RecordError: LocalizedError {
        case unreadableAmount(String)

        var errorDescription: String? {
            switch self {
            case .unreadableAmount(let text):
                let shown = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return shown.isEmpty
                    ? "«Команды» не передали сумму. В действии «Записать оплату Apple Pay» в поле «Сумма» должна стоять сумма из входных данных автоматизации."
                    : "Не удалось прочитать сумму «\(shown)». Трата не записана."
            }
        }
    }

    /// Повторный запуск автоматизации для той же оплаты не создаёт вторую трату.
    private static let repeatWindow: TimeInterval = 120

    /// Записывает оплату как расход: на счёт карты (по умолчанию Kaspi), с категорией
    /// по правилам, памяти мерчантов и словарю, с ₽-эквивалентом и метками по датам.
    ///
    /// Если оплата была в другой валюте, чем счёт, сумма в валюте счёта считается
    /// по курсу — примерно; точную даст выписка. Если курса ещё нет, трата
    /// записывается в валюте оплаты без счёта, чтобы не исказить его остаток.
    @MainActor
    static func record(
        amountText: String,
        merchant: String,
        card: String?,
        at date: Date = .now,
        context: ModelContext
    ) throws -> Recorded {
        guard let paid = WalletAmountParser.parse(amountText) else {
            throw RecordError.unreadableAmount(amountText)
        }

        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let merchantName = trimmedMerchant.isEmpty ? "Apple Pay" : trimmedMerchant

        let accounts = try context.fetch(FetchDescriptor<Account>())
        let account = self.account(for: card, in: accounts)
        let accountCurrency = CurrencyDisplay.normalizedCode(from: account?.currencyCode ?? "KZT")
        let paidCurrency = paid.currencyCode.map { CurrencyDisplay.normalizedCode(from: $0) } ?? accountCurrency

        if let repeated = try recentPayment(merchant: merchantName, amount: paid.value, currency: paidCurrency, before: date, context: context) {
            return Recorded(message: "Уже записано: \(summary(of: repeated))")
        }

        let rates = RubRateTable.load(context: context)
        var amount = paid.value
        var currencyCode = accountCurrency
        var foreignAmount: Double?
        var foreignCurrencyCode: String?
        var fromAccount = account

        if paidCurrency != accountCurrency {
            if let rubPerPaid = rates.rubPerUnit(paidCurrency, on: date),
               let rubPerAccountUnit = rates.rubPerUnit(accountCurrency, on: date),
               rubPerAccountUnit > 0 {
                amount = ((paid.value * rubPerPaid / rubPerAccountUnit) * 100).rounded() / 100
                foreignAmount = paid.value
                foreignCurrencyCode = paidCurrency
            } else {
                currencyCode = paidCurrency
                fromAccount = nil
            }
        }

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let category = CategoryRuleEngine.match(
            operationType: KaspiOperationType.purchase.rawValue,
            details: merchantName,
            rules: try context.fetch(FetchDescriptor<CategoryRule>()),
            existingCategories: try context.fetch(FetchDescriptor<ExpenseCategoryItem>()),
            memory: MerchantCategoryMemory(transactions: transactions)
        )

        let transaction = Transaction(
            date: date,
            kindRaw: TransactionKind.expense.rawValue,
            amount: amount,
            currencyCode: currencyCode,
            details: merchantName,
            foreignAmount: foreignAmount,
            foreignCurrencyCode: foreignCurrencyCode,
            rubAmount: rates.rubAmount(amount: amount, currencyCode: currencyCode, on: date),
            categoryName: category?.category,
            subcategoryName: category?.subcategory,
            walletMerchant: merchantName,
            fromAccount: fromAccount
        )

        context.insert(transaction)
        // Метки, в даты которых попала оплата (например, поездка).
        TransactionTagSync.applyPeriodTags(to: [transaction], context: context)
        try context.save()

        return Recorded(message: "Записано: \(summary(of: transaction))")
    }

    // MARK: - Statement

    /// Строки выписки заменяют найденные в ней оплаты из Apple Pay: у банка точная
    /// сумма и название, по которым сходятся следующие импорты. Метки, заметка,
    /// выбранная вручную категория и своё название переходят на строку выписки,
    /// сама оплата удаляется.
    ///
    /// Вызывать после вставки новых операций импорта и до проставления меток по датам.
    /// Возвращает копии удалённых оплат — по ним «Отменить импорт» вернёт их.
    @MainActor
    static func replaceWithStatement(_ confirmations: [WalletConfirmation], context: ModelContext) -> [RemovedDuplicate] {
        let removedAt = Date()

        return confirmations.map { confirmation in
            let payment = confirmation.payment
            let statement = confirmation.statementTransaction

            // Переименовали после оплаты — своё название важнее банковского.
            if let walletMerchant = payment.walletMerchant, payment.details != walletMerchant {
                statement.details = payment.details
            }

            // Категория из Wallet-названия пригодится, если по названию из выписки
            // ничего не нашлось; выбранная вручную — всегда.
            if payment.isCategoryManuallySet == true || (!hasCategory(statement) && hasCategory(payment)) {
                statement.categoryName = payment.categoryName
                statement.subcategoryName = payment.subcategoryName
                statement.isCategoryManuallySet = payment.isCategoryManuallySet
            }

            if let note = payment.note, !note.isEmpty, (statement.note ?? "").isEmpty {
                statement.note = note
            }

            for tag in payment.tagNames ?? [] {
                statement.addTag(tag)
            }
            for tag in payment.manuallyExcludedTagNames ?? [] {
                statement.removeTag(tag, manual: true)
            }

            let removed = RemovedDuplicate(payment, keptDetails: statement.details, removedAt: removedAt, automatic: true)
            context.delete(payment)
            return removed
        }
    }

    // MARK: - Helpers

    /// Счёт карты: если её название содержит название счёта — он, иначе Kaspi
    /// (Kaspi Gold — карта, с которой платят через Apple Pay).
    private static func account(for card: String?, in accounts: [Account]) -> Account? {
        let active = accounts.filter { !$0.isArchived }
        if let card = card?.trimmingCharacters(in: .whitespacesAndNewlines), !card.isEmpty,
           let named = active.first(where: { card.localizedCaseInsensitiveContains($0.name) }) {
            return named
        }
        return AccountLookup.kaspi(in: active)
    }

    @MainActor
    private static func recentPayment(
        merchant: String,
        amount: Double,
        currency: String,
        before date: Date,
        context: ModelContext
    ) throws -> Transaction? {
        let since = date.addingTimeInterval(-repeatWindow)
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= since })

        return try context.fetch(descriptor).first { transaction in
            transaction.walletMerchant == merchant
                && CurrencyDisplay.normalizedCode(from: transaction.foreignCurrencyCode ?? transaction.currencyCode) == currency
                && abs((transaction.foreignAmount ?? transaction.amount) - amount) < 0.005
        }
    }

    private static func hasCategory(_ transaction: Transaction) -> Bool {
        guard let category = transaction.categoryName else { return false }
        return CategoryNameNormalizer.normalize(category) != "другое"
    }

    /// «−2 450 KZT · Magnum · Еда»; у валютной оплаты — сумма в валюте и примерно в тенге.
    private static func summary(of transaction: Transaction) -> String {
        var amount = "−\(format(transaction.amount, transaction.currencyCode))"
        if let foreignAmount = transaction.foreignAmount, let foreignCurrency = transaction.foreignCurrencyCode {
            amount = "−\(format(foreignAmount, foreignCurrency)) (≈ \(format(transaction.amount, transaction.currencyCode)))"
        }
        return [amount, transaction.details, transaction.categoryName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private static func format(_ value: Double, _ currencyCode: String) -> String {
        let number = value.formatted(
            .number
                .locale(Locale(identifier: "ru_RU"))
                .precision(.fractionLength(0...2))
        )
        return "\(number) \(CurrencyDisplay.symbol(for: currencyCode))"
    }
}

/// Оплата из Apple Pay и строка выписки, которая её заменяет.
struct WalletConfirmation {
    let payment: Transaction
    /// Новая операция из выписки — она уже среди операций для вставки.
    let statementTransaction: Transaction
}
