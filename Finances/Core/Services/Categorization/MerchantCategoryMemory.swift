import Foundation

/// Категория (и подкатегория), которую определила автокатегоризация.
struct CategoryMatch: Equatable {
    let category: String
    let subcategory: String?
}

/// Название мерчанта из выписки в удобном для сравнения виде.
enum MerchantName {
    /// Префиксы платёжных агрегаторов: к самому магазину отношения не имеют.
    private static let processorPrefixes: Set<String> = [
        "VNPAY", "MPOS", "PAYOO", "SQ", "SP", "SUMUP", "ZETTLE", "IZ", "PAYPAL", "WWW", "COM"
    ]

    /// Слова в верхнем регистре: всё, кроме букв и цифр, — разделители.
    static func words(_ details: String) -> [String] {
        details.uppercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Ключ мерчанта без номеров точек и кодов операций: «PAYOO MCDONALDS 0053A»
    /// и «PAYOO MCDONALDS 0017B» → «MCDONALDS», «7ELEVEN_1127» → «7ELEVEN».
    static func key(_ details: String) -> String {
        let meaningful = words(details).filter { word in
            let digits = word.filter(\.isNumber).count
            return digits < 3 && digits < word.count && !processorPrefixes.contains(word)
        }
        return meaningful.isEmpty ? words(details).joined(separator: " ") : meaningful.joined(separator: " ")
    }
}

/// Запоминает, какую категорию пользователь сам выбрал для мерчанта,
/// и подставляет её новым операциям того же мерчанта.
struct MerchantCategoryMemory {
    static let empty = MerchantCategoryMemory(transactions: [])

    private var byMerchant: [String: (match: CategoryMatch, date: Date)] = [:]

    init(transactions: [Transaction]) {
        for transaction in transactions where transaction.isCategoryManuallySet == true && transaction.kind == .expense {
            guard let category = transaction.categoryName else { continue }
            let key = MerchantName.key(transaction.details)
            guard !key.isEmpty else { continue }

            // Последний выбор пользователя важнее старых.
            if let existing = byMerchant[key], existing.date > transaction.date { continue }
            byMerchant[key] = (CategoryMatch(category: category, subcategory: transaction.subcategoryName), transaction.date)
        }
    }

    func match(for details: String) -> CategoryMatch? {
        byMerchant[MerchantName.key(details)]?.match
    }
}
