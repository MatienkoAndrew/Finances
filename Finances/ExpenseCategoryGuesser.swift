import Foundation

enum ExpenseCategoryGuesser {
    static func guessCategoryName(for operationType: String, details: String) -> String? {
        let text = details.uppercased()

        if operationType == "Снятие" {
            return "Снятие наличных"
        }

        if operationType == "Перевод" {
            return "Перевод"
        }

        if operationType == "Пополнение" {
            return nil
        }

        if text.contains("CHATGPT") || text.contains("SPOTIFY") || text.contains("APPLE.COM BILL") {
            return "Подписки"
        }

        if text.contains("GRAB") {
            return "Транспорт"
        }

        if text.contains("COFFEE") || text.contains("HIGHLANDS") || text.contains("STARBUCKS") {
            return "Кофе"
        }

        if text.contains("MCDONALDS")
            || text.contains("PHO")
            || text.contains("PAPASTEAK")
            || text.contains("BRUNCH")
            || text.contains("BURGERS")
            || text.contains("CUISINE")
            || text.contains("ROASTERY")
            || text.contains("BANH XEO")
            || text.contains("SECTION 30")
            || text.contains("LAVA 79")
            || text.contains("43 FACTORY")
            || text.contains("BIKINIBOTTOM") {
            return "Еда"
        }

        if text.contains("MART")
            || text.contains("MARKET")
            || text.contains("AAUMINIMART")
            || text.contains("4BMART")
            || text.contains("GOOD MART")
            || text.contains("FULL MARKET")
            || text.contains("CJ MART")
            || text.contains("HEREMART")
            || text.contains("TONY MART") {
            return "Продукты"
        }

        if text.contains("AGODA") || text.contains("HOTEL") || text.contains("INN") {
            return "Путешествия"
        }

        if text.contains("MOBIFIT")
            || text.contains("FITNESS") {
            return "Здоровье"
        }

        if text.contains("CAP TREO")
            || text.contains("NAM THANH")
            || text.contains("MOONMILK")
            || text.contains("NEWYORK")
            || text.contains("ELEMENT") {
            return "Покупки"
        }

        return nil
    }
}
