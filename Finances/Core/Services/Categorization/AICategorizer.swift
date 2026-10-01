import Foundation
import SwiftData
import SwiftUI
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Ответы нейросети по мерчантам: каждый мерчант спрашиваем один раз,
/// а при следующих импортах категория берётся отсюда.
enum AIMerchantCategoryCache {
    private struct Entry: Codable {
        let category: String
        let subcategory: String?
    }

    private static let storageKey = "aiMerchantCategories"
    private static var entries: [String: Entry] = load()

    static func contains(_ merchantKey: String) -> Bool {
        entries[merchantKey] != nil
    }

    static func match(for details: String) -> CategoryMatch? {
        entries[MerchantName.key(details)].map { CategoryMatch(category: $0.category, subcategory: $0.subcategory) }
    }

    static func store(_ match: CategoryMatch, for merchantKey: String) {
        entries[merchantKey] = Entry(category: match.category, subcategory: match.subcategory)
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Все сохранённые ответы: ключ мерчанта → категория.
    static var all: [String: CategoryMatch] {
        entries.mapValues { CategoryMatch(category: $0.category, subcategory: $0.subcategory) }
    }

    /// Забыть ответ по мерчанту (пользователь выбрал категорию сам или попросил забыть).
    static func remove(_ merchantKey: String) {
        guard entries.removeValue(forKey: merchantKey) != nil else { return }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Переносит сохранённые ответы на новую структуру категорий.
    static func remap(_ transform: (CategoryMatch) -> CategoryMatch) {
        entries = entries.mapValues { entry in
            let match = transform(CategoryMatch(category: entry.category, subcategory: entry.subcategory))
            return Entry(category: match.category, subcategory: match.subcategory)
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private static func load() -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return entries
    }
}

/// Угадывает категорию нейросетью Apple Intelligence (на устройстве, офлайн) для
/// мерчантов, которых не распознали правила, история выбора и словарь.
/// Догадка — не ручной выбор: её можно поменять, и правила её перезапишут.
enum AICategorizer {
    private static let log = Logger(subsystem: "andrewmatienko.Finances", category: "AICategorizer")
    static let enabledKey = "aiCategorizationEnabled"
    private static let fallbackCategory = "другое"
    private static var isRunning = false
    /// Почему прервался последний запуск (модель не готова и т.п.), nil — всё прошло.
    private(set) static var lastFailure: String?

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// nil — нейросеть доступна; иначе — почему нет.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "Устройство не поддерживает Apple Intelligence"
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Включи Apple Intelligence в настройках iPhone"
            case .unavailable(.modelNotReady):
                return "Модель ещё загружается — попробуй позже"
            case .unavailable:
                return "Apple Intelligence недоступна"
            }
        }
        #endif
        return "Нужна iOS 26 и iPhone с Apple Intelligence"
    }

    /// Категоризирует операции, оставшиеся в «Другом». Возвращает, сколько операций обновлено.
    @discardableResult
    static func runIfEnabled(context: ModelContext) async -> Int {
        guard isEnabled, !isRunning, unavailableReason == nil else { return 0 }
        isRunning = true
        lastFailure = nil
        defer { isRunning = false }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await categorize(context: context)
        }
        #endif
        return 0
    }

    private static func isFallback(_ transaction: Transaction) -> Bool {
        transaction.categoryName.map(CategoryNameNormalizer.normalize).map { $0 == fallbackCategory } ?? true
    }

    private static func needsGuess(_ transaction: Transaction) -> Bool {
        !transaction.isDeleted
            && transaction.kind == .expense
            && transaction.isCategoryManuallySet != true
            && isFallback(transaction)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func categorize(context: ModelContext) async -> Int {
        guard let transactions = try? context.fetch(FetchDescriptor<Transaction>()),
              let categories = try? context.fetch(FetchDescriptor<ExpenseCategoryItem>()) else { return 0 }

        let options = CategoryOption.options(for: categories)
        guard options.count > 1 else { return 0 }

        let groups = Dictionary(grouping: transactions.filter(needsGuess)) { MerchantName.key($0.details) }
            .filter { !$0.key.isEmpty && !AIMerchantCategoryCache.contains($0.key) }
            .sorted { $0.value.count > $1.value.count }

        var updated = 0
        for (key, group) in groups {
            guard let sample = group.first(where: { !$0.isDeleted }) else { continue }

            let label: String
            do {
                label = try await guessLabel(for: sample, options: options.map(\.label))
            } catch LanguageModelSession.GenerationError.guardrailViolation,
                    LanguageModelSession.GenerationError.refusal {
                // Модель отказалась отвечать про этого мерчанта — больше не спрашиваем.
                log.info("Refused for \(key, privacy: .public)")
                AIMerchantCategoryCache.store(CategoryMatch(category: "Другое", subcategory: nil), for: key)
                continue
            } catch {
                // Модель недоступна или занята — продолжим при следующем запуске.
                log.error("Stopped: \(String(describing: error), privacy: .public)")
                lastFailure = "Модель Apple Intelligence пока не готова на этом устройстве — попробуем при следующем запуске."
                break
            }

            log.debug("\(key, privacy: .public) → \(label, privacy: .public)")
            guard let option = options.first(where: { $0.label == label }) else { continue }
            AIMerchantCategoryCache.store(option.match, for: key)

            guard CategoryNameNormalizer.normalize(option.match.category) != fallbackCategory else { continue }
            for transaction in group where needsGuess(transaction) {
                transaction.categoryName = option.match.category
                transaction.subcategoryName = option.match.subcategory
                updated += 1
            }
            try? context.save()
        }
        return updated
    }

    @available(iOS 26.0, *)
    private static func guessLabel(for transaction: Transaction, options: [String]) async throws -> String {
        let schema = try GenerationSchema(
            root: DynamicGenerationSchema(name: "Category", anyOf: options),
            dependencies: []
        )
        // Названия мерчантов — не пользовательский контент для генерации, а данные
        // для классификации; строгий фильтр ложно срабатывает на «KUSH HOUSE» и т.п.
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: prompt(for: transaction),
            schema: schema,
            options: GenerationOptions(sampling: .greedy)
        )
        return try response.content.value(String.self)
    }

    private static let instructions = """
        You categorize card payments from a bank statement by the merchant name.
        The card owner is from Kazakhstan and often travels (Vietnam, Thailand, Korea, Sri Lanka, etc.).
        Merchant names are uppercase, often truncated, and may be transliterated Vietnamese, Thai or Korean:
        "NHA HANG" means restaurant, "CA PHE" coffee, "QUAN" eatery, "SPA" massage, "KHACH SAN" hotel.
        Prefixes like VNPAY, MPOS, PAYOO, HKD, CTY, CONG TY, TNHH are payment processors or company forms, not the shop.
        The payment currency and amount hint at the country and the kind of place.
        Choose the single most likely category from the list. Prefer a specific category even if unsure.
        Choose "Другое" only if the name is a person's name or gives no clue at all.
        """

    private static func prompt(for transaction: Transaction) -> String {
        var lines = ["Merchant: \(transaction.details)"]
        if let amount = transaction.foreignAmount, let currency = transaction.foreignCurrencyCode {
            lines.append("Paid: \(Int(amount.rounded())) \(currency)")
        } else {
            lines.append("Paid: \(Int(transaction.amount.rounded())) \(transaction.currencyCode)")
        }
        return lines.joined(separator: "\n")
    }
    #endif
}

/// Вариант ответа для нейросети: «Еда · Кафе» → категория и подкатегория пользователя.
private struct CategoryOption {
    let label: String
    let match: CategoryMatch

    /// Категории расходов и их подкатегории; «Другое» — последним вариантом.
    static func options(for categories: [ExpenseCategoryItem]) -> [CategoryOption] {
        let excluded: Set<String> = ["другое", "перевод", "снятие наличных"]
        var options: [CategoryOption] = []

        for category in categories where !excluded.contains(CategoryNameNormalizer.normalize(category.name)) {
            let subs = DefaultSubcategoryDefinitions.subcategories(for: category.name) ?? []
            options.append(CategoryOption(
                label: category.name,
                match: CategoryMatch(category: category.name, subcategory: DefaultSubcategoryDefinitions.defaultSubcategory(for: category.name))
            ))
            for sub in subs where sub.name != DefaultSubcategoryDefinitions.defaultName {
                options.append(CategoryOption(
                    label: "\(category.name) · \(sub.name)",
                    match: CategoryMatch(category: category.name, subcategory: sub.name)
                ))
            }
        }

        if let other = categories.first(where: { CategoryNameNormalizer.normalize($0.name) == "другое" }) {
            options.append(CategoryOption(label: other.name, match: CategoryMatch(category: other.name, subcategory: nil)))
        }
        return options
    }
}

/// Переключатель в настройках: угадывать категории нейросетью и запустить сейчас.
struct AICategorizationRow: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isEnabled = AICategorizer.isEnabled
    @State private var isRunning = false
    @State private var resultMessage: String?

    var body: some View {
        let unavailableReason = AICategorizer.unavailableReason

        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isEnabled) {
                Label("Угадывать категории нейросетью", systemImage: "sparkles")
            }
            .onChange(of: isEnabled) { _, newValue in
                AICategorizer.isEnabled = newValue
                if newValue { runNow() }
            }

            Group {
                if let unavailableReason {
                    Text(unavailableReason)
                } else if isRunning {
                    Text("Нейросеть разбирает «Другое»…")
                } else if let resultMessage {
                    Text(resultMessage)
                } else {
                    Text("Apple Intelligence на устройстве подбирает категорию тому, что не распознали правила и словарь. Данные не покидают iPhone.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func runNow() {
        guard !isRunning else { return }
        isRunning = true
        Task {
            let updated = await AICategorizer.runIfEnabled(context: modelContext)
            isRunning = false
            if let failure = AICategorizer.lastFailure {
                resultMessage = failure
            } else {
                resultMessage = updated == 0
                    ? "Новых догадок нет — всё, что можно, уже распознано."
                    : "Нейросеть определила категорию у \(updated) операций."
            }
        }
    }
}
