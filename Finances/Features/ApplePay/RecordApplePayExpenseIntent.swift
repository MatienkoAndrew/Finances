//
//  RecordApplePayExpenseIntent.swift
//  Finances
//
//  Действие для «Команд»: записывает оплату Apple Pay. Подключается к автоматизации
//  «Транзакция», которая срабатывает после каждой оплаты картой из Wallet
//  с телефона или часов и передаёт сумму и магазин. Выполняется в фоне —
//  приложение не открывается, а итог приходит уведомлением.
//

import AppIntents
import SwiftData

struct RecordApplePayExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Записать оплату Apple Pay"

    static let description = IntentDescription(
        "Добавляет расход в Finances. Подставь сумму и продавца из автоматизации «Транзакция»: тогда каждая оплата телефоном будет появляться в приложении сама."
    )

    /// Сумма числом. Текстом нельзя: «Команды» падают, переводя в текст сумму
    /// в чужой валюте (оплата в долларах с тенговой карты). Тип «сумма с валютой»
    /// они из автоматизации не заполняют и просят ввести сумму вручную.
    /// Валюта — местная по часовому поясу телефона.
    @Parameter(title: "Сумма", description: "Сумма оплаты из автоматизации «Транзакция».")
    var amount: Double

    @Parameter(title: "Магазин", description: "Продавец из автоматизации «Транзакция».")
    var merchant: String

    @Parameter(title: "Карта", description: "Необязательно. Счёт выбирается по названию карты, иначе — Kaspi.")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Записать \(\.$amount) — \(\.$merchant)") {
            \.$card
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let recorded = try ApplePayExpenses.record(
            value: Decimal(amount),
            currencyCode: LocalCurrency.code(),
            merchant: merchant,
            card: card,
            context: AppModelContainer.shared.mainContext
        )
        return .result(dialog: "\(recorded.message)")
    }
}
