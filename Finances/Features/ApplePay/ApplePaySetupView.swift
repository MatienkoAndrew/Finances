//
//  ApplePaySetupView.swift
//  Finances
//
//  Как подключить траты из Apple Pay: автоматизация «Транзакция» в «Командах»
//  с действием «Записать оплату Apple Pay». Ниже — оплаты, которые ждут выписку.
//

import SwiftUI
import SwiftData

struct ApplePaySetupView: View {
    @Environment(\.openURL) private var openURL

    @Query(
        filter: #Predicate<Transaction> { $0.walletMerchant != nil && $0.fingerprint == nil },
        sort: \Transaction.date,
        order: .reverse
    )
    private var awaitingStatement: [Transaction]

    private static let steps = [
        "Открой «Команды» → «Автоматизация» → «Новая автоматизация» (или «+», если автоматизации уже есть).",
        "Выбери «Транзакция», отметь карту Kaspi Gold и «Немедленный запуск», нажми «Далее».",
        "Нажми «Создать новую быструю команду» и добавь действие «Записать оплату Apple Pay» из Finances.",
        "Нажми «Сумма» → «Выбрать переменную» → «Входные данные команды», затем нажми на неё и выбери сумму. В «Магазин» так же подставь продавца.",
        "Готово. После оплаты придёт уведомление вроде «Записано: −2\u{00A0}450\u{00A0}KZT · Magnum · Еда»."
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                stepsSection
                statementSection

                if !awaitingStatement.isEmpty {
                    pendingSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Траты из Apple Pay")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIcon(systemImage: "wave.3.right", color: .cyan, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("Оплатили телефоном — трата уже в приложении")
                    .font(.headline)
                Text("После каждой оплаты картой из Wallet iPhone запускает автоматизацию в «Командах», и она записывает сумму и магазин в Finances. Приложение при этом не открывается.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader("Как подключить")

            SettingsCard {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 {
                        SettingsDivider()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.cyan.gradient, in: Circle())
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }

                        Text(step)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                }

                SettingsDivider()

                Button {
                    if let url = URL(string: "shortcuts://") {
                        openURL(url)
                    }
                } label: {
                    SettingsRow(title: "Открыть «Команды»", systemImage: "square.2.layers.3d.fill", color: .indigo)
                }
                .buttonStyle(SettingsPressStyle())
            }

            Text("Если вместо траты пришло «Команды не передали сумму», значит, Wallet не отдаёт сумму для этой карты.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var statementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader("А выписка?")

            Text("Выписку по-прежнему стоит импортировать. Её строка найдёт оплату по дню и сумме и заменит её: сумма станет точной, название — как у банка, а метки, заметка и выбранная вручную категория сохранятся. Kaspi QR, переводы и оплаты внутри Kaspi в Apple Pay не попадают — они придут только с выпиской.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader("Ждут выписку") {
                Text("\(awaitingStatement.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            SettingsCard {
                ForEach(Array(awaitingStatement.prefix(5).enumerated()), id: \.element.persistentModelID) { index, transaction in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 16)
                    }
                    pendingRow(transaction)
                }
            }
        }
    }

    private func pendingRow(_ transaction: Transaction) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.details)
                    .lineLimit(1)
                Text(transaction.date.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: "ru_RU"))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("−\(Self.format(transaction.foreignAmount ?? transaction.amount)) \(CurrencyDisplay.symbol(for: transaction.foreignCurrencyCode ?? transaction.currencyCode))")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "ru_RU")).precision(.fractionLength(0...2)))
    }
}
